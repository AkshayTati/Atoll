#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-debug}"
APP="$ROOT/build/Atoll.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-Islet Development}"

swift build -c "$CONFIG" --product Atoll
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Atoll" "$APP/Contents/MacOS/Atoll"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/Atoll.icns" ]; then
  cp "$ROOT/Resources/Atoll.icns" "$APP/Contents/Resources/Atoll.icns"
fi
if [ -d "$ROOT/Resources/CatSprites" ]; then
  cp -R "$ROOT/Resources/CatSprites" "$APP/Contents/Resources/CatSprites"
fi

"$ROOT/scripts/build-helper.sh"
cp "$ROOT/build/libIsletMediaRemote.dylib" "$APP/Contents/Resources/libIsletMediaRemote.dylib"
cp "$ROOT/Resources/mediaremote-helper.pl" "$APP/Contents/Resources/mediaremote-helper.pl"

if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP" >/dev/null
  echo "signed with '$SIGN_IDENTITY'"
else
  codesign --force --sign - --timestamp=none "$APP" >/dev/null
  echo "signed ad-hoc (run scripts/setup-signing.sh for a stable identity)"
fi

echo "built $APP"
