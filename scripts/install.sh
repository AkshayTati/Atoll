#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/Applications/Atoll.app"

cd "$ROOT"
./scripts/bundle.sh

mkdir -p "$HOME/Applications"
pkill -x Atoll >/dev/null 2>&1 || true
pkill -x Islet >/dev/null 2>&1 || true
pkill -x Nook >/dev/null 2>&1 || true
sleep 0.2

rm -rf "$DEST"
cp -R "$ROOT/build/Atoll.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
rm -rf "$HOME/Applications/Islet.app" "$HOME/Applications/Nook.app"

# Remove the build copy so LaunchServices/Spotlight only point at the real
# install. `make run` will rebuild it for development.
rm -rf "$ROOT/build/Atoll.app" "$ROOT/build/Islet.app" "$ROOT/build/Nook.app"

open "$DEST"

echo "installed $DEST"
echo "Enable 'Launch at Login' from the Atoll menu-bar icon."
