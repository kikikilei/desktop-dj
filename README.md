# Desktop DJ

Desktop DJ is a tiny pixel-art music companion for macOS. It reads the
system-wide Now Playing state, so it works with Spotify, NetEase Music,
Apple Music, and other players that publish playback metadata to macOS.

> Personal toy, shared for noncommercial learning and collaboration. Commercial
> use is not permitted. See [LICENSE.md](LICENSE.md).

## Download

[Download Desktop DJ for macOS](https://github.com/kikikilei/desktop-dj/releases/latest)

Installation:

1. Download `Desktop-DJ-macOS.zip` from the latest release.
2. Unzip it and drag `Desktop DJ.app` into Applications.
3. On first launch, Control-click or right-click the app, choose **Open**, and
   confirm **Open** once more.

Desktop DJ currently uses an ad-hoc signature and is not notarized through the
Apple Developer Program, so opening it by double-click alone may show an
unidentified-developer warning.

## Interaction

- Drag the cat or headphones to move Desktop DJ.
- Double-click the cat to collapse it into headphones.
- Double-click the headphones to expand the full DJ again.
- Right-click anywhere on the companion for Previous, Play/Pause, Next,
  Collapse/Expand, and Quit.
- Hover over the compact headphones for quick playback controls.
- Use the menu-bar cat icon for Show/Hide, playback controls, reset position,
  and skin management.
- Choose **Copy Diagnostic Report** from either menu when playback detection
  fails. The report is copied locally, omits song and account details, and is
  never uploaded automatically.

Desktop DJ opens expanded on every launch. The expanded player is 230 × 213
points; the compact headphones remain 80 × 88 points.

Cow Cat playback now rotates between the main 12 fps loop, a second dance loop,
and a low-probability beer-break easter egg. Alternate clips always return to
the main loop, and the beer clip has a two-minute cooldown.

## Build

Run `./build.sh`. It creates a universal app for Intel and Apple Silicon with
macOS 13.0 as the deployment target. The verified distributable is:

`Build/Desktop DJ.zip`

The unpacked `Build/Desktop DJ.app` is also available for local testing. Share
the zip: the build extracts that archive into a temporary directory and repeats
all compatibility and signature checks before it succeeds.

The app builds and embeds a universal `nowplaying-cli` 2.1.0 bridge from its
vendored source archive. Its matching license, README, and source archive are
included under `Contents/Resources/ThirdParty`. A separate Homebrew
installation is not required.

Now Playing metadata is polled without artwork; album artwork is fetched and
pixelated only when the visible track changes. Bridge calls have a timeout so
an unresponsive music provider cannot freeze future updates.

## Contributing and design

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting code or assets.
- Use [DESIGN-HANDOFF.md](DESIGN-HANDOFF.md) for animation and layered deck
  exports.
- See [ROADMAP.md](ROADMAP.md) for the next interactive deck milestones.
- This project is source-available for noncommercial use; it is not offered
  under an OSI-approved open-source license.

## Compatibility

- macOS 13 Ventura or later
- Intel and Apple Silicon Macs

The build finishes by checking the app metadata, both CPU architectures, every
embedded executable's deployment target, and the code signature. See
`COMPATIBILITY.md` for the release policy.
