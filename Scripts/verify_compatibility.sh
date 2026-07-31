#!/bin/zsh
set -euo pipefail

APP_DIR="${1:?Usage: verify_compatibility.sh /path/to/App.app [minimum-version]}"
EXPECTED_MINIMUM="${2:-13.0}"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
BINARIES=(
  "$APP_DIR/Contents/MacOS/DesktopDJ"
  "$APP_DIR/Contents/Resources/Bridge/bin/nowplaying-cli"
  "$APP_DIR/Contents/Resources/Bridge/lib/nowplaying-cli/MediaRemoteMini.dylib"
)

declared_minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")
if [[ "$declared_minimum" != "$EXPECTED_MINIMUM" ]]; then
  print -u2 "Expected LSMinimumSystemVersion $EXPECTED_MINIMUM, found $declared_minimum"
  exit 1
fi

for binary in "${BINARIES[@]}"; do
  for arch in arm64 x86_64; do
    if ! lipo -archs "$binary" | tr ' ' '\n' | grep -qx "$arch"; then
      print -u2 "Missing $arch slice: $binary"
      exit 1
    fi

    minimum=$(otool -arch "$arch" -l "$binary" |
      awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}')
    if [[ "$minimum" != "$EXPECTED_MINIMUM" ]]; then
      print -u2 "Expected $binary ($arch) minos $EXPECTED_MINIMUM, found $minimum"
      exit 1
    fi
  done
done

codesign --verify --deep --strict "$APP_DIR"
print "Compatibility verification passed: macOS $EXPECTED_MINIMUM+, arm64 + x86_64"
