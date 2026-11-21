#!/bin/sh
set -eu

VERSION="1.0.0"
ARCH="arm64"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="DroidMac"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="DroidMac-v${VERSION}-${ARCH}.dmg"
ZIP_NAME="DroidMac-v${VERSION}-${ARCH}.zip"

echo "==> Building DroidMac release v${VERSION}..."
"$ROOT_DIR/Scripts/build_app.sh"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$DMG_NAME" "$DIST_DIR/$ZIP_NAME"

echo "==> Creating release ZIP ($ZIP_NAME)..."
(cd "$BUILD_DIR" && zip -qry "$DIST_DIR/$ZIP_NAME" "$APP_NAME.app")

echo "==> Creating release DMG ($DMG_NAME)..."
DMG_TMP="$(mktemp -d)"
trap 'rm -rf "$DMG_TMP"' EXIT

cp -R "$APP_BUNDLE" "$DMG_TMP/$APP_NAME.app"
ln -s /Applications "$DMG_TMP/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TMP" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_NAME"

echo "==> Generating checksums..."
(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > SHA256SUMS.txt)

echo "==> Release artifacts ready in $DIST_DIR:"
ls -lh "$DIST_DIR"
cat "$DIST_DIR/SHA256SUMS.txt"
