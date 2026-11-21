#!/bin/bash
set -euo pipefail

# DroidMac Installer for macOS (Apple Silicon)
# Repository: https://github.com/sinarahmany/DroidMac

VERSION="0.1.0-alpha"
REPO="sinarahmany/DroidMac"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/DroidMac-v${VERSION}-arm64.dmg"
INSTALL_DIR="/Applications"

echo ""
echo "  ================================================================"
echo "    DroidMac v${VERSION} — Native Android Apps & Games on macOS"
echo "  ================================================================"
echo ""

# 1. Architecture check
ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
    echo "❌ Error: DroidMac is optimized exclusively for Apple Silicon (M1/M2/M3/M4) Macs."
    echo "Detected architecture: $ARCH"
    exit 1
fi

echo "✅ Detected Apple Silicon architecture ($ARCH)"

# 2. Check Homebrew prerequisites
echo "==> Checking prerequisites..."
MISSING_TOOLS=()

if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Homebrew is required to install runtime dependencies."
    echo "Install Homebrew first from https://brew.sh"
    exit 1
fi

if ! brew list openjdk@21 >/dev/null 2>&1 && ! /usr/libexec/java_home -v 21 >/dev/null 2>&1; then
    MISSING_TOOLS+=("openjdk@21")
fi

if ! command -v scrcpy >/dev/null 2>&1; then
    MISSING_TOOLS+=("scrcpy")
fi

if ! command -v adb >/dev/null 2>&1; then
    MISSING_TOOLS+=("android-platform-tools")
fi

if ! command -v sdkmanager >/dev/null 2>&1; then
    MISSING_TOOLS+=("android-commandlinetools")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "==> Installing missing runtime dependencies via Homebrew: ${MISSING_TOOLS[*]}..."
    for tool in "${MISSING_TOOLS[@]}"; do
        if [ "$tool" = "android-platform-tools" ] || [ "$tool" = "android-commandlinetools" ]; then
            brew install --cask "$tool"
        else
            brew install "$tool"
        fi
    done
else
    echo "✅ All Homebrew prerequisites are installed."
fi

# 3. Download and Install DroidMac.app
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Downloading DroidMac v${VERSION}..."
DMG_PATH="$TMP_DIR/DroidMac.dmg"
if curl -fsSL -o "$DMG_PATH" "$DOWNLOAD_URL"; then
    echo "==> Mounting DMG..."
    MOUNT_DIR="$TMP_DIR/mount"
    hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
    
    echo "==> Installing DroidMac.app to $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR/DroidMac.app"
    cp -R "$MOUNT_DIR/DroidMac.app" "$INSTALL_DIR/DroidMac.app"
    
    hdiutil detach "$MOUNT_DIR" -quiet
    echo "✅ Successfully installed DroidMac.app in $INSTALL_DIR/DroidMac.app"
else
    echo "ℹ️  Release DMG not yet published on GitHub Releases. Building locally from source..."
    TMP_SRC="$TMP_DIR/src"
    git clone --depth 1 "https://github.com/${REPO}.git" "$TMP_SRC"
    cd "$TMP_SRC"
    ./Scripts/build_app.sh
    echo "✅ Built and installed DroidMac.app locally!"
fi

echo ""
echo "🎉 Installation complete!"
echo "Open DroidMac from your Applications folder or run:"
echo "   open /Applications/DroidMac.app"
echo ""
