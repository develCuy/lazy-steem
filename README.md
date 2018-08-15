(This project is deprecated due to the death of STEEM's cli_wallet. Long live to cli_wallet!)

# lazy-steem - Easy tools for lazy STEEM shareholders

STEEM is very nice but it has some pretty boring repetitive tasks that could be automated.

# Installation

Assuming you are on Ubuntu/Debian, please run the following commands:

    # apt install uuid-dev libssl-dev
    # luarocks install seawolf luasec dkjson

# Available tools

## publish_feed.lua

This script runs publish_feed cli_wallet command atomagically. Average STEEM market price is
calculated from public APIs (currently Poloniex, Bittrex, Coinmarketcap, Blockchaing and Coindesk).

Usage example:

    ./publish_feed.lua http://localhost:8093
 
 Where `http://localhost:8093` is the remote address of your running cli_wallet instance, which
 should be unlocked by the time this script is invoked.
 
