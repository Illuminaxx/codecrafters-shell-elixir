#!/bin/sh
#
# This script is used to compile your program on CodeCrafters
#
# This runs before .codecrafters/run.sh
#
# Learn more: https://codecrafters.io/program-interface

set -e # Exit on failure

# Compile the NIF (skip if no C compiler available)
if command -v cc >/dev/null 2>&1; then
  mkdir -p priv
  ERLANG_PATH=$(elixir -e 'IO.puts(:code.root_dir())')
  cc -O3 -std=c99 -fPIC -shared -I"$ERLANG_PATH/usr/include" -o priv/tty_nif.so c_src/tty_nif.c || true
fi

# Build the escript
mix escript.build
mv codecrafters_shell /tmp/codecrafters-build-shell-elixir
