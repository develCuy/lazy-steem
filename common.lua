local seawolf = require 'seawolf'.__build('contrib')
local xtable = seawolf.contrib.seawolf_table
local http, https = require 'socket.http', require 'ssl.https'
local json, ltn12 = require 'dkjson', require 'ltn12'

local function api_call(url)
  if nil == url then
    return
  end

  local chunks = xtable()
  local r, c, h, s = ('https' == url:sub(1,5) and https or http).request{
    url = url,
    sink = ltn12.sink.table(chunks),
  }

  local response = chunks:concat()

  return json.decode(response)
end

local function cli_wallet_call(server, method, params)
  local request = {
    jsonrpc = '2.0',
    id = 1,
    method = method,
    params = params or {},
  }
  local jsonRequest = json.encode(request)
  local chunks = xtable()

  local r, c, h, s = ('https' == server:sub(1,5) and https or http).request{
    url = server,
    method = 'POST',
    headers = {
      ['content-type'] = 'application/json',
      ['content-length'] = jsonRequest:len()
    },
    source = ltn12.source.string(jsonRequest),
    sink = ltn12.sink.table(chunks),
  }

  if nil == s then
    error(("ERROR: Can't connect to %s"):format(server))
  end

  local response = chunks:concat()

  return json.decode(response)
end

return {
  api_call = api_call,
  cli_wallet_call = cli_wallet_call,
}
