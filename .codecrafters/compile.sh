#!/bin/sh
#
# This script is used to compile your program on CodeCrafters
#
# This runs before .codecrafters/run.sh
#
# Learn more: https://codecrafters.io/program-interface

set -e # Exit on failure

# Build the escript first
mix escript.build

# Compile the raw_wrapper C program
if command -v cc >/dev/null 2>&1; then
  cc -o /tmp/codecrafters-build-shell-elixir-wrapper c_src/raw_wrapper.c
  # Move escript to a different location
  mv codecrafters_shell /tmp/codecrafters-build-shell-elixir-escript
  # Create a wrapper script that calls the C wrapper with the escript
  cat > /tmp/codecrafters-build-shell-elixir <<'EOF'
#!/bin/sh
echo "[shell-wrapper] About to execute C wrapper" >&2
ls -la /tmp/codecrafters-build-shell-elixir-wrapper >&2
exec /tmp/codecrafters-build-shell-elixir-wrapper /tmp/codecrafters-build-shell-elixir-escript "$@"
EOF
  chmod +x /tmp/codecrafters-build-shell-elixir
else
  # No C compiler, just use escript directly
  mv codecrafters_shell /tmp/codecrafters-build-shell-elixir
fi
