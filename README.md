# Islet

A dynamic-island-style notch app for macOS, built for one person: me.

## Status

Phase 3 — notch shell, multi-media, calendar, and audio output control
integrated into the media panel.

- Every Now Playing client (Chrome, Firefox, Music, Spotify, …) gets its own
  row with artwork/app icon, title, artist, progress, and **per-client**
  play/pause/next/previous.
- Multi-client access goes through a small Perl-hosted helper because macOS
  15.4+ blocks direct MediaRemote access from third-party apps. The helper
  lives in `Sources/MediaRemoteHelper` and is bundled into the app.
- The island grows vertically when more than three clients are active.
- The old Sound tab is gone. Output device + volume live in the media panel.
- Output switching is **system-wide**, not per-app. macOS has no public
  per-app output API; true routing would require a process-tap mixer or a
  virtual audio driver.

## Dependencies

- macOS 14+
- Command Line Tools (Swift 5.9+)
- `media-control` (Homebrew): `brew tap ungive/media-control && brew install media-control`
- Optional stable signing identity: `make signing` (self-signed, no Apple
  developer account)

## Build & run

```sh
make run
```

This builds `build/Islet.app`, signs it (stable self-signed identity when
available), and launches it through LaunchServices. Logs are streamed to
`build/islet.log`.

```sh
make stop     # kill it
make probe    # print current now-playing info via the MediaRemote probe
```

Requirements: macOS 14+, Command Line Tools (Swift 5.9+). No Xcode, no Apple
developer account, no sandbox, no notarization.

## Layout

```
Sources/Islet/            the app (AppKit shell + SwiftUI content)
Sources/MediaRemoteHelper/ ObjC dylib loaded by Perl for multi-client access
Sources/mediaspike/       throwaway CLI probe for the private MediaRemote API
Sources/MediaRemoteShim/  tiny C shim around MediaRemote (dlopen)
Resources/Info.plist      bundle metadata (LSUIElement, usage strings)
Resources/mediaremote-helper.pl  Perl loader for the helper dylib
scripts/bundle.sh         build + .app assembly + codesign
scripts/build-helper.sh   compile the MediaRemote helper dylib
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
