#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/Build"
FINAL_APP_DIR="$BUILD_DIR/Desktop DJ.app"
FINAL_ZIP="$BUILD_DIR/Desktop DJ.zip"
STAGE_DIR="$(mktemp -d '/tmp/desktop-dj-build.XXXXXX')"
APP_DIR="$STAGE_DIR/Desktop DJ.app"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
ARCHITECTURES=(arm64 x86_64)
BINARY_DIR="$STAGE_DIR/Binaries"
BRIDGE_SOURCE_ARCHIVE="$ROOT_DIR/Vendor/nowplaying-cli/source/nowplaying-cli-v2.1.0.tar.gz"
trap 'rm -rf "$STAGE_DIR"' EXIT

python3 "$ROOT_DIR/Scripts/prepare_assets.py"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$BINARY_DIR"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ROOT_DIR/Assets/logo-head.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ROOT_DIR/Assets/logo-head.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ROOT_DIR/Assets/logo-head.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ROOT_DIR/Assets/logo-head.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ROOT_DIR/Assets/logo-head.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ROOT_DIR/Assets/logo-head.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ROOT_DIR/Assets/logo-head.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ROOT_DIR/Assets/logo-head.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ROOT_DIR/Assets/logo-head.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ROOT_DIR/Assets/logo-head.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

for arch in "${ARCHITECTURES[@]}"; do
  swiftc \
    -swift-version 5 \
    -parse-as-library \
    -target "${arch}-apple-macosx${DEPLOYMENT_TARGET}" \
    "$ROOT_DIR"/Sources/DesktopDJ/*.swift \
    -o "$BINARY_DIR/DesktopDJ-$arch" \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    -framework CoreImage
done
lipo -create "$BINARY_DIR"/DesktopDJ-* -output "$APP_DIR/Contents/MacOS/DesktopDJ"

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Assets/cat-playing-deck-v2-prepared.png" "$APP_DIR/Contents/Resources/cat-playing.png"
cp "$ROOT_DIR/Assets/cat-sleeping-deck-v2-prepared.png" "$APP_DIR/Contents/Resources/cat-sleeping.png"
cp "$ROOT_DIR/Assets/cat-switching-deck-v2-prepared.png" "$APP_DIR/Contents/Resources/cat-switching.png"
cp "$ROOT_DIR/Assets/logo-head.png" "$APP_DIR/Contents/Resources/logo-head.png"
cp "$ROOT_DIR/Assets/animations/cat-playing-loop.gif" "$APP_DIR/Contents/Resources/cat-playing-loop.gif"
cp "$ROOT_DIR/Assets/animations/cat-resting-loop.gif" "$APP_DIR/Contents/Resources/cat-resting-loop.gif"
cp "$ROOT_DIR/Assets/animations/cat-switching-once.gif" "$APP_DIR/Contents/Resources/cat-switching-once.gif"
cp "$ROOT_DIR/Assets/compact/headphones-upright-compact.png" "$APP_DIR/Contents/Resources/headphones-upright.png"
cp "$ROOT_DIR/Assets/compact/headphones-flat-compact.png" "$APP_DIR/Contents/Resources/headphones-flat.png"
cp "$ROOT_DIR/LICENSE.md" "$APP_DIR/Contents/Resources/Desktop-DJ-License.md"
ditto "$ROOT_DIR/Assets/skins" "$APP_DIR/Contents/Resources/Skins"

mkdir -p \
  "$APP_DIR/Contents/Resources/Bridge" \
  "$APP_DIR/Contents/Resources/ThirdParty/nowplaying-cli/source"

BRIDGE_SOURCE_ROOT="$STAGE_DIR/nowplaying-cli-source"
mkdir -p "$BRIDGE_SOURCE_ROOT"
tar -xzf "$BRIDGE_SOURCE_ARCHIVE" -C "$BRIDGE_SOURCE_ROOT"
BRIDGE_ORIGINAL_SOURCE="$BRIDGE_SOURCE_ROOT/nowplaying-cli-2.1.0"

for arch in "${ARCHITECTURES[@]}"; do
  bridge_arch_source="$STAGE_DIR/nowplaying-cli-$arch"
  ditto "$BRIDGE_ORIGINAL_SOURCE" "$bridge_arch_source"
  MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" make \
    -C "$bridge_arch_source" \
    CFLAGS="-O3 -arch $arch -mmacosx-version-min=$DEPLOYMENT_TARGET" \
    >/dev/null
  cp "$bridge_arch_source/nowplaying-cli" "$BINARY_DIR/nowplaying-cli-$arch"
  cp \
    "$bridge_arch_source/build/mediaremote-mini/MediaRemoteMini.dylib" \
    "$BINARY_DIR/MediaRemoteMini-$arch.dylib"
done

mkdir -p \
  "$APP_DIR/Contents/Resources/Bridge/bin" \
  "$APP_DIR/Contents/Resources/Bridge/lib/nowplaying-cli"
lipo -create \
  "$BINARY_DIR"/nowplaying-cli-* \
  -output "$APP_DIR/Contents/Resources/Bridge/bin/nowplaying-cli"
lipo -create \
  "$BINARY_DIR"/MediaRemoteMini-*.dylib \
  -output "$APP_DIR/Contents/Resources/Bridge/lib/nowplaying-cli/MediaRemoteMini.dylib"
ditto "$ROOT_DIR/Vendor/nowplaying-cli/share" "$APP_DIR/Contents/Resources/Bridge/share"
cp "$ROOT_DIR/Vendor/nowplaying-cli/LICENSE" "$APP_DIR/Contents/Resources/ThirdParty/nowplaying-cli/LICENSE"
cp "$ROOT_DIR/Vendor/nowplaying-cli/README.md" "$APP_DIR/Contents/Resources/ThirdParty/nowplaying-cli/README.md"
cp \
  "$BRIDGE_SOURCE_ARCHIVE" \
  "$APP_DIR/Contents/Resources/ThirdParty/nowplaying-cli/source/"

chmod -R u+w "$APP_DIR"
chmod +x "$APP_DIR/Contents/Resources/Bridge/bin/nowplaying-cli"
xattr -dr com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -dr 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
xattr -cr "$APP_DIR"
xattr -dr com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -dr 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
codesign --force --sign - "$APP_DIR/Contents/Resources/Bridge/bin/nowplaying-cli"
codesign --force --sign - "$APP_DIR/Contents/Resources/Bridge/lib/nowplaying-cli/MediaRemoteMini.dylib"
codesign --force --deep --sign - "$APP_DIR"
xattr -dr com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -dr 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
"$ROOT_DIR/Scripts/verify_compatibility.sh" "$APP_DIR" "$DEPLOYMENT_TARGET"

rm -rf "$FINAL_APP_DIR"
ditto --norsrc "$APP_DIR" "$FINAL_APP_DIR"

rm -f "$FINAL_ZIP"
ditto --norsrc -c -k --keepParent "$APP_DIR" "$FINAL_ZIP"

PACKAGE_TEST_DIR="$STAGE_DIR/package-test"
mkdir -p "$PACKAGE_TEST_DIR"
ditto -x -k "$FINAL_ZIP" "$PACKAGE_TEST_DIR"
"$ROOT_DIR/Scripts/verify_compatibility.sh" \
  "$PACKAGE_TEST_DIR/Desktop DJ.app" \
  "$DEPLOYMENT_TARGET"

echo "$FINAL_ZIP"
