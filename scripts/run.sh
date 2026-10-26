#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/bundle.sh

pkill -x Atoll >/dev/null 2>&1 || true
pkill -x Islet >/dev/null 2>&1 || true
if [[ -f "$ROOT/build/log.pid" ]]; then
  kill "$(cat "$ROOT/build/log.pid")" >/dev/null 2>&1 || true
fi
sleep 0.2

mkdir -p "$ROOT/build"
: >"$ROOT/build/atoll.log"
/usr/bin/log stream --predicate 'process == "Atoll"' --level info --style compact \
  >"$ROOT/build/atoll.log" 2>&1 &
echo $! >"$ROOT/build/log.pid"

# Launch through LaunchServices so TCC attributes Calendar access to Atoll
# rather than to the terminal.
if ! open -n "$ROOT/build/Atoll.app"; then
  echo "could not launch through LaunchServices; open build/Atoll.app manually"
  exit 1
fi

echo "Atoll launched"
echo "log: $ROOT/build/atoll.log"
