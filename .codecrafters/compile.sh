#!/bin/sh
#
# This script is used to compile your program on CodeCrafters
#
# This runs before .codecrafters/run.sh
#
# Learn more: https://codecrafters.io/program-interface

set -e # Exit on failure

# Compile the NIF
mkdir -p priv
ERLANG_PATH=$(elixir -e 'IO.puts(:code.root_dir())')
gcc -O3 -std=c99 -fPIC -shared -I"$ERLANG_PATH/usr/include" -o priv/tty_nif.so c_src/tty_nif.c

# Build the escript
mix escript.build
mv codecrafters_shell /tmp/codecrafters-build-shell-elixir
