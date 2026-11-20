# DroidMac

Run Android apps and 3D games on macOS (Apple Silicon) as standalone native macOS windows and `.app` launchers.

## How It Works

- **Native ARM64 Virtualization:** Runs an isolated ARM64 Android 15 virtual machine on Apple's `Hypervisor.framework` with zero x86 CPU translation.
- **Metal GPU Acceleration:** Routes guest OpenGL ES & Vulkan graphics through `gfxstream` to Apple Silicon's GPU (`-gpu host`), enabling smooth 60 FPS apps and games.
- **Per-App Native Windows:** Uses Android multi-display virtual displays (`scrcpy` v5 + SDL3 + Apple VideoToolbox hardware decode + CoreAudio) with `--flex-display` so each Android app runs in its own resizable macOS window.
- **Real macOS `.app` Launchers:** Export any installed Android app or game to `~/Applications/DroidMac Apps/<AppName>.app` with its extracted icon so it launches straight from Spotlight, Launchpad, or the Dock.
- **Safe & Isolated:** Zero `sudo`, zero kernel extensions, zero macOS SIP modifications, loopback-only ADB (`emulator-5554`), strict APK archive validation, and automatic clean VM shutdown on quit.

## Quick Start

1. Build and install `DroidMac.app` to `~/Applications/DroidMac.app`:
   ```bash
   ./Scripts/build_app.sh
   ```
2. Open **DroidMac** (`open ~/Applications/DroidMac.app`) and click **Start Android Engine** (or run Setup if setting up on a new Mac).
3. Launch any Android app in its own native window, drag-and-drop `.apk` / `.xapk` / `.apks` files to install, or open **Google Play Store** to install apps and games.
4. Click `...` on any app → **Add to Mac Applications (.app)** to create a standalone Spotlight/Dock launcher.

## CLI Usage

```bash
CLI="$HOME/Library/Application Support/DroidMac/bin/DroidMacCLI"

"$CLI" status
"$CLI" setup
"$CLI" start
"$CLI" apps
"$CLI" install /path/to/app.apk
"$CLI" launch --package com.android.settings --profile adaptive --title "Settings"
"$CLI" wrap --package com.android.settings --name "Android Settings" --profile adaptive
"$CLI" stop
```

## Running Tests

```bash
swift test
```
