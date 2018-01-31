local seawolf = require 'seawolf'.__build('contrib', [[text]], [[variable]])
local xtable, print_r = seawolf.contrib.seawolf_table, seawolf.variable.print_r
local trim, explode = seawolf.text.trim, seawolf.text.explode
local http, https = require 'socket.http', require 'ssl.https'
local json, ltn12 = require 'dkjson', require 'ltn12'

function debug.print(msg)
  if nil == msg then
    msg = [[nil]]
  end
  io.stderr:write( ([[table]] == type(msg) or [[userdata]] == type(msg)) and print_r(msg, 1) or tostring(msg))
  io.stderr:write "\n"
end

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

--[[ Parse params and options.
]]
local function parse_args(args)
  local options, params = {}, {}
  for k, v in pairs(args or {}) do
    if k > 0 then
      if [[--]] == v:sub(1, 2) then
        local parts = explode([[=]], v:sub(3))
        options[parts[1]] = trim(parts[2])
      else
        params[#params + 1] = trim(v)
      end
    end
  end

  return options, params
end

return {
  api_call = api_call,
  cli_wallet_call = cli_wallet_call,
  parse_args = parse_args,
}
