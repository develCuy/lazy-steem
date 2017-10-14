local seawolf = require 'seawolf'.__build('text', 'variable', 'contrib')
local print_r, xtable = seawolf.variable.print_r, seawolf.contrib.seawolf_table
local json, ltn12, tonumber = require 'dkjson', require 'ltn12', tonumber
local trim = seawolf.text.trim
local http, https = require 'socket.http', require 'ssl.https'

local server = trim(arg[1])

if '' == server then
  print "Usage: publish_feed witness protocol://server:port\n"
  print "  witness   The witness username"
  print "  protocol  Whether http or https"
  print "  port      Example: 8093"
  print "\n"
  os.exit(1)
end

-- Detailed settings for each pair
local apis = {}
apis = {
  coinmarketcap = {
    cache = {url = nil, data = nil},
    pairs = {
      steem = {usd = true},
      sbd = {usd = true},
    },
    alias = {
      usd = 'USD',
      sbd = 'steem-dollars',
    },
    get_url = function (from, to)
      return ('https://api.coinmarketcap.com/v1/ticker/%s/?convert=%s'):format(from, to)
    end,
    get_price = function(from, to, data)
      if data and data[1] then
        return tonumber(data[1].price_usd)
      end
    end
  },
  poloniex = {
    cache = {url = nil, data = nil},
    pairs = {
      btc = {steem = true, sbd = true, usd = true},
    },
    alias = {
      usd = 'USDT',
      btc = 'BTC',
      steem = 'STEEM',
      sbd = 'SBD',
    },
    get_url = function (from, to)
      return 'https://poloniex.com/public?command=returnTicker'
    end,
    get_price = function(from, to, data)
      if to == 'USDT' then
        to = from
        from = 'USDT'
      end
      local pair = ('%s_%s'):format(from, to)
      if data[pair] then
        return tonumber(data[pair].last)
      end
    end
  },
  bittrex = {
    cache = {url = nil, data = nil},
    pairs = {
      btc = {steem = true, sbd = true},
    },
    alias = {},
    get_url = function (from, to)
      return ('https://bittrex.com/api/v1.1/public/getticker?market=%s-%s'):format(from, to)
    end,
    get_price = function (from, to, data)
      if data and data.success and data.result then
        return tonumber(data.result.Last)
      end
    end,
  },
  blockchain = {
    cache = {url = nil, data = nil},
    pairs = {
      btc = {usd = true},
    },
    alias = {
      usd = 'USD',
    },
    get_url = function (from, to)
      return 'https://blockchain.info/ticker'
    end,
    get_price = function (from, to, data)
      if data and data[to] then
        return data[to].last
      end
    end,
  },
  coindesk = {
    cache = {url = nil, data = nil},
    pairs = {
      btc = {usd = true},
    },
    alias = {
      usd = 'USD',
    },
    get_url = function (from, to)
      return 'https://api.coindesk.com/v1/bpi/currentprice.json'
    end,
    get_price = function (from, to, data)
      if data and data.bpi and data.bpi[to] then
        return data.bpi[to].rate_float
      end
    end,
  },
}

local function api_call(url)
  if nil == url then
    return
  end

  local chunks = xtable()
  local r, c, h, s = https.request{
    url = url,
    sink = ltn12.sink.table(chunks),
  }

  local response = chunks:concat()

  return json.decode(response)
end

-- Fetch current prices from ALL active pairs
local function fetch_market_prices()
  local result = {}

  for provider, api in pairs(apis) do
    for from, tos in pairs(api.pairs) do
      for to, status in pairs(tos) do
        if status then
          -- Build URL to fetch data
          local url = api.get_url(api.alias[from] or from, api.alias[to] or to)

          -- Test cache
          if api.cache.url ~= url then
            api.cache.url = url

            -- Fetch data from URL
            api.cache.data = api_call(url)
          end

          if api.cache.data then
            local price = api.get_price(api.alias[from] or from, api.alias[to] or to, api.cache.data)
            if price then
              local pair = ('%s_%s'):format(from, to)
              if nil == result[pair] then
                result[pair] = {}
              end
              result[pair][provider] = price
            end
          end
        end
      end
    end
  end

  return result
end

local function calc_pairs_averages(prices)
  local result = {}

  for pair, markets in pairs(prices) do
    local total, count = 0, 0
    for _, price in pairs(markets) do
      total = total + price
      count = count + 1
    end
    result[pair] = total / count
  end

  return result
end

local function calc_price(coin, data)
  local proxied_price
  if data['btc_usd'] and data['btc_' .. coin] then
    proxied_price = tonumber(('%f'):format(data['btc_usd'] * data['btc_' .. coin]))
  end

  if data[coin .. '_usd'] and proxied_price then
    -- avg(market_price, proxied)
    return (data[coin .. '_usd'] + proxied_price)/2
  elseif nil ~= data[coin .. '_usd'] then
    -- market_price
    return data[coin .. '_usd']
  elseif nil ~= proxied_price then
    -- proxied
    return proxied_price
  end
end

local function calc_sbd_price(data)
  local proxied_sbd_price
  if data['btc_usd'] and data['btc_sbd'] then
    proxied_sbd_price = tonumber(('%f'):format(data['btc_usd'] * data['btc_sbd']))
  end

  if data.sbd_usd and proxied_sbd_price then
    print 'avg(market_price, proxied)'
    return (data.sbd_usd + proxied_sbd_price)/2
  elseif nil ~= data.sbd_usd then
    print 'market_price'
    return data.sbd_usd
  elseif nil ~= proxied_sbd_price then
    print 'proxied'
    return proxied_sbd_price
  end
end

local function cli_wallet_call(method, params)
  local request = {
    jsonrpc = '2.0',
    id = 1,
    method = method,
    params = params or {},
  }
  local jsonRequest = json.encode(request)
  local chunks = xtable()

  local r, c, h = ('https' == server:sub(1,5) and https or http).request{
    url = server,
    method = 'POST',
    headers = {
      ['content-type'] = 'application/json',
      ['content-length'] = jsonRequest:len()
    },
    source = ltn12.source.string(jsonRequest),
    sink = ltn12.sink.table(chunks),
  }

  local response = chunks:concat()

  return json.decode(response)
end

local function publish_feed(witness, base, quote)
  local result = cli_wallet_call(
    'publish_feed',
    {witness, {base = ("%.3f SBD"):format(base), quote = ("%.3f STEEM"):format(quote)}, true},
    true
  )
end

local market_prices = fetch_market_prices()
local pairs_averages = calc_pairs_averages(market_prices)

-- Calculate STEEM price in USD
local steem_price = calc_price('steem', pairs_averages)
local sbd_price = calc_price('sbd', pairs_averages)

publish_feed('dropahead', sbd_price, steem_price)
