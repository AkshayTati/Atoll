#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/Applications/Islet.app"

cd "$ROOT"
./scripts/bundle.sh

mkdir -p "$HOME/Applications"
pkill -x Islet >/dev/null 2>&1 || true
sleep 0.2

rm -rf "$DEST"
cp -R "$ROOT/build/Islet.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# Remove the build copy so LaunchServices/Spotlight only point at the real
# install. `make run` will rebuild it for development.
rm -rf "$ROOT/build/Islet.app"

open "$DEST"

echo "installed $DEST"
echo "Enable 'Launch at Login' from the Islet menu-bar icon."
