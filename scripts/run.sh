#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/bundle.sh

pkill -x Islet >/dev/null 2>&1 || true
if [[ -f "$ROOT/build/log.pid" ]]; then
  kill "$(cat "$ROOT/build/log.pid")" >/dev/null 2>&1 || true
fi
sleep 0.2

mkdir -p "$ROOT/build"
: >"$ROOT/build/islet.log"
/usr/bin/log stream --predicate 'process == "Islet"' --level info --style compact \
  >"$ROOT/build/islet.log" 2>&1 &
echo $! >"$ROOT/build/log.pid"

# Launch through LaunchServices so TCC attributes Calendar access to Islet
# rather than to the terminal.
open -n "$ROOT/build/Islet.app"

echo "Islet launched"
echo "log: $ROOT/build/islet.log"
