#!/usr/bin/env lua5.1

local seawolf = require 'seawolf'.__build([[text]], [[variable]])
local trim, tonumber = seawolf.text.trim, tonumber
local explode, empty = seawolf.text.explode, seawolf.variable.empty

local common = require 'common'
local api_call = common.api_call
local cli_wallet_call = common.cli_wallet_call
local parse_args = common.parse_args

-- Parse params and options
local options, params = parse_args(arg)
local witness = trim(params[1])
local server = trim(params[2])

if '' == witness or '' == server then
  print "Usage: publish_feed [OPTION]... [WITNESS NAME] [CLI_WALLET SERVER]"
  print [[]]
  print [[  Available options:]]
  print [[  --bias[=NUMBER]   Set the bias percentage]]
  print [[]]
  print [[  Parameters:]]
  print "  WITNESS NAME       The witness username"
  print "  CLI_WALLET SERVER  Format: protocol://server:port"
  print "                       protocol  Whether http or https"
  print "                       server    Example: localhost"
  print "                       port      Example: 8093"
  print [[]]
  print [[]]
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
  hitbtc = {
    cache = {url = nil, data = nil},
    pairs = {
      btc = {usd = true, steem = true, sbd = true},
    },
    alias = {
      usd = [[USD]],
      btc = [[BTC]],
      steem = [[STEEM]],
      sbd = [[SBD]],
    },
    get_url = function (from, to)
      if [[STEEM]] == to or [[SBD]] == to then
        return ([[https://api.hitbtc.com/api/2/public/ticker/%s%s]]):format(to, from)
      else
        return ([[https://api.hitbtc.com/api/2/public/ticker/%s%s]]):format(from, to)
      end
    end,
    get_price = function (from, to, data)
      if data then
        return data.last
      end
    end,
  },
}

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

local function publish_feed(witness, base, quote)
  local result = cli_wallet_call(
    server,
    'publish_feed',
    {witness, {base = ("%.3f SBD"):format(base), quote = ("%.3f STEEM"):format(quote)}, true}
  )
end

local market_prices = fetch_market_prices()
local pairs_averages = calc_pairs_averages(market_prices)

-- Calculate STEEM quote
local steem_quote = 1.000
if not empty(options.bias) then
  steem_quote = 1 - ((options.bias*1/100)/(1 + options.bias*1/100))
end

-- Calculate SBD price
local sbd_price = calc_price('sbd', pairs_averages)

-- Calculate SBD base
local sbd_base = sbd_price * steem_quote

publish_feed(witness, sbd_base, steem_quote)
