#!/usr/bin/env lua5.1

local seawolf = require 'seawolf'.__build('text')
local trim, tonumber = seawolf.text.trim, tonumber

local common = require 'common'
local api_call = common.api_call
local cli_wallet_call = common.cli_wallet_call

local account = trim(arg[1])
local server = trim(arg[2])

if '' == account or '' == server then
  print "Usage: claim_reward account protocol://server:port\n"
  print "  account   The account name"
  print "  protocol  Whether http or https"
  print "  server    Example: localhost"
  print "  port      Example: 8093"
  print "\n"
  os.exit(1)
end

local function get_account(account_name)
  return cli_wallet_call(
    server,
    'get_account',
    {account_name}
  )
end

local function claim_reward_balance(account, reward_steem, reward_sbd, reward_vests)
  return cli_wallet_call(
    server,
    'claim_reward_balance',
    {account, reward_steem, reward_sbd, reward_vests, true}
  )
end

local data = get_account(account)

if data and data.result then
  print(([[Rewards balance for @%s:

%s
%s
%s

Claiming rewards...]]):format(
    account,
    data.result.reward_steem_balance,
    data.result.reward_sbd_balance,
    data.result.reward_vesting_balance
  ))

  claim_reward_balance(
    account,
    data.result.reward_steem_balance,
    data.result.reward_sbd_balance,
    data.result.reward_vesting_balance
  )
end
