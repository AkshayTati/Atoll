#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Resources/icon-1024.png"
ICONSET="$ROOT/Resources/Islet.iconset"

swift "$ROOT/scripts/make-icon.swift" "$SOURCE"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

cp "$SOURCE" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/Islet.icns"
rm -rf "$ICONSET" "$SOURCE"

echo "built $ROOT/Resources/Islet.icns"
