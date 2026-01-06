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

# Use pre-compiled raw_wrapper binary
if [ -f c_src/raw_wrapper ]; then
  echo "[compile] Using pre-compiled wrapper binary"
  cp c_src/raw_wrapper /tmp/codecrafters-build-shell-elixir-wrapper
  chmod +x /tmp/codecrafters-build-shell-elixir-wrapper
  echo "[compile] Wrapper binary copied successfully"
  # Move escript to a different location
  mv codecrafters_shell /tmp/codecrafters-build-shell-elixir-escript
  # Create a wrapper script that calls the C wrapper with the escript
  cat > /tmp/codecrafters-build-shell-elixir <<'EOF'
#!/bin/sh
echo "[shell-wrapper] About to execute C wrapper" >&2
exec /tmp/codecrafters-build-shell-elixir-wrapper /tmp/codecrafters-build-shell-elixir-escript "$@"
EOF
  chmod +x /tmp/codecrafters-build-shell-elixir
  echo "[compile] Created wrapper script at /tmp/codecrafters-build-shell-elixir"
else
  echo "[compile] No pre-compiled wrapper found, using escript directly"
  # No wrapper binary, just use escript directly
  mv codecrafters_shell /tmp/codecrafters-build-shell-elixir
fi
