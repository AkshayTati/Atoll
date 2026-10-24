#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/bundle.sh

pkill -x Islet >/dev/null 2>&1 || true
sleep 0.2

mkdir -p "$ROOT/build"
"$ROOT/build/Islet.app/Contents/MacOS/Islet" >"$ROOT/build/islet.log" 2>&1 &
PID=$!
echo "$PID" >"$ROOT/build/islet.pid"

echo "Islet running (pid $PID)"
echo "log: $ROOT/build/islet.log"
