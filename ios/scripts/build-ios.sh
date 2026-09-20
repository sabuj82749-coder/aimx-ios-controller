#!/usr/bin/env bash
# Builds the AIM-X iOS controller unsigned (device release slice) and stages a
# .xcarchive you can later re-sign. Designed to run on a macOS host with Xcode
# 15.x, or inside the CI runner (see .github/workflows/build-ios.yml).
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$IOS_DIR/AIMXController.xcodeproj"
SCHEME="AimXController"
BUILD="$IOS_DIR/build"

echo "==> Building unsigned Release device slice"
xcodebuild \
  -project "$PROJ" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

echo "==> Archiving for later signing"
xcodebuild \
  -project "$PROJ" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD" \
  -archivePath "$BUILD/AIMXController.xcarchive" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  archive

APP="$BUILD/AIMXController.xcarchive/Products/Applications/AimXController.app"
echo "==> Done. Built app: $APP"
test -d "$APP" && echo "OK: app present."
