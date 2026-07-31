# Compatibility policy

Desktop DJ currently targets macOS 13 Ventura and later.

Every distributable build must meet all of these checks:

1. `LSMinimumSystemVersion` is `13.0`.
2. The app executable and embedded playback bridge contain both `arm64` and
   `x86_64` slices.
3. Every Mach-O slice has a deployment target of `13.0`, rather than silently
   inheriting the build Mac's current SDK version.
4. The final app passes strict code-signature verification.
5. Playback metadata, play/pause, previous, next, seek, dragging, compact mode,
   and context menus receive a smoke test before a release is shared.

`nowplaying-cli` uses Apple's private MediaRemote framework. It has worked on
the supported systems tested by its upstream project, but a future macOS update
can change that private interface. Keep the bridge isolated behind
`NowPlayingService` so it can be replaced without changing the UI.

Before widening support below macOS 13, test the full SwiftUI app and bridge on
real hardware or a clean virtual machine. Do not lower only the plist value.

