#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/libIsletMediaRemote.dylib"

mkdir -p "$ROOT/build"
clang -dynamiclib -fobjc-arc -fblocks -O2 \
  -framework Foundation \
  -framework CoreFoundation \
  -o "$OUT" \
  "$ROOT/Sources/MediaRemoteHelper/MediaRemoteHelper.m"

echo "built $OUT"
