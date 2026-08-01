#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
TEST_DIR="$(mktemp -d '/tmp/desktop-dj-tests.XXXXXX')"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc \
  -swift-version 5 \
  -parse-as-library \
  "$ROOT_DIR/Sources/DesktopDJ/ProcessRunner.swift" \
  "$ROOT_DIR/Sources/DesktopDJ/Models.swift" \
  "$ROOT_DIR/Sources/DesktopDJ/NowPlayingService.swift" \
  "$ROOT_DIR/Sources/DesktopDJ/DiagnosticReport.swift" \
  "$ROOT_DIR/Tests/RegressionTests.swift" \
  -o "$TEST_DIR/RegressionTests" \
  -framework AppKit \
  -framework CoreImage

"$TEST_DIR/RegressionTests"
