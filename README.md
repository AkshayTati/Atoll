# Islet

A dynamic-island-style notch app for macOS, built for one person: me.

## Status

Phase 0 — spike. The shell (notch panel, hover expand/collapse) plus a
MediaRemote probe. No real modules yet.

## Build & run

```sh
make run
```

This builds `build/Islet.app`, ad-hoc signs it, and launches the binary with
stdout going to `build/islet.log`.

```sh
make stop     # kill it
make probe    # print current now-playing info via the MediaRemote probe
```

Requirements: macOS 14+, Command Line Tools (Swift 5.9+). No Xcode, no Apple
developer account, no sandbox, no notarization.

## Layout

```
Sources/Islet/            the app (AppKit shell + SwiftUI content)
Sources/mediaspike/       throwaway CLI probe for the private MediaRemote API
Sources/MediaRemoteShim/  tiny C shim around MediaRemote (dlopen)
Resources/Info.plist      bundle metadata (LSUIElement, usage strings)
scripts/bundle.sh         build + .app assembly + codesign
```

## Notes

- The panel is an `NSPanel` at `statusBar + 1`, non-activating, joined to all
  spaces, positioned from `NSScreen.safeAreaInsets` and
  `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
- Collapsed shape is the notch plus a few points of black "lip" so it is
  visible and catches the eye. Hover expands it; hover out collapses it.
- Media uses the private `MediaRemote.framework`. This may break with any
  macOS update. Fallbacks: MediaRemoteAdapter, ScriptingBridge, per-app
  AppleScript.
