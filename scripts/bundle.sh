#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-debug}"
APP="$ROOT/build/Islet.app"

swift build -c "$CONFIG" --product Islet
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Islet" "$APP/Contents/MacOS/Islet"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature for now. Stable identity (self-signed cert) comes in
# before we add Calendar/TCC in phase 4.
codesign --force --sign - --timestamp=none "$APP" >/dev/null

echo "built $APP"
