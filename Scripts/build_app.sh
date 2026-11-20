#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/DroidMac.app"
SUPPORT_BIN="$HOME/Library/Application Support/DroidMac/bin"
USER_APPS="$HOME/Applications"

echo "==> Building DroidMac & DroidMacCLI (release)..."
cd "$ROOT_DIR"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling DroidMac.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_DIR/DroidMac" "$APP_BUNDLE/Contents/MacOS/DroidMac"
cp "$BIN_DIR/DroidMacCLI" "$APP_BUNDLE/Contents/MacOS/DroidMacCLI"
chmod +x "$APP_BUNDLE/Contents/MacOS/DroidMac" "$APP_BUNDLE/Contents/MacOS/DroidMacCLI"

# Also install CLI helper into ~/Library/Application Support/DroidMac/bin so generated .app launchers always find it
mkdir -p "$SUPPORT_BIN"
cp "$BIN_DIR/DroidMacCLI" "$SUPPORT_BIN/DroidMacCLI"
chmod +x "$SUPPORT_BIN/DroidMacCLI"

# Generate clean macOS AppIcon.icns for DroidMac.app
ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT

swift - <<'SWIFT' "$ICON_TMP/icon_1024.png"
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments[1]
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let rect = CGRect(x: 96, y: 96, width: 832, height: 832)
let path = CGPath(roundedRect: rect, cornerWidth: 188, cornerHeight: 188, transform: nil)
ctx.addPath(path)
ctx.clip()

let top = CGColor(red: 0.12, green: 0.56, blue: 0.44, alpha: 1)
let bottom = CGColor(red: 0.07, green: 0.31, blue: 0.28, alpha: 1)
let grad = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 928), end: CGPoint(x: 512, y: 96), options: [])

// Crisp macOS-style window frame emblem
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.26))
ctx.setLineWidth(14)
ctx.addPath(CGPath(roundedRect: CGRect(x: 220, y: 230, width: 584, height: 564), cornerWidth: 72, cornerHeight: 72, transform: nil))
ctx.strokePath()

// Minimalist Android head silhouette
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
ctx.addPath(CGPath(roundedRect: CGRect(x: 332, y: 340, width: 360, height: 290), cornerWidth: 145, cornerHeight: 145, transform: nil))
ctx.fillPath()

// Twin antennas
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
ctx.setLineWidth(24)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 420, y: 615))
ctx.addLine(to: CGPoint(x: 368, y: 710))
ctx.move(to: CGPoint(x: 604, y: 615))
ctx.addLine(to: CGPoint(x: 656, y: 710))
ctx.strokePath()

// Eyes
ctx.setFillColor(CGColor(red: 0.09, green: 0.39, blue: 0.33, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 422, y: 468, width: 42, height: 42))
ctx.fillEllipse(in: CGRect(x: 560, y: 468, width: 42, height: 42))

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
SWIFT

ICONSET="$ICON_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16     "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ICON_TMP/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DroidMac</string>
    <key>CFBundleDisplayName</key>
    <string>DroidMac</string>
    <key>CFBundleIdentifier</key>
    <string>com.droidmac.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>DroidMac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing DroidMac.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

mkdir -p "$USER_APPS"
rm -rf "$USER_APPS/DroidMac.app"
cp -R "$APP_BUNDLE" "$USER_APPS/DroidMac.app"

echo "==> Built: $APP_BUNDLE"
echo "==> Installed: $USER_APPS/DroidMac.app"
echo "==> CLI helper: $SUPPORT_BIN/DroidMacCLI"
