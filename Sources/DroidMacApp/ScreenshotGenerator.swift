import SwiftUI
import AppKit
import DroidMacCore

@MainActor
public enum ScreenshotGenerator {

    public struct WindowChrome<Content: View>: View {
        let title: String
        let width: CGFloat
        let height: CGFloat
        let content: Content

        public init(title: String, width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) {
            self.title = title
            self.width = width
            self.height = height
            self.content = content()
        }

        public var body: some View {
            VStack(spacing: 0) {
                // macOS Titlebar
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                        Circle()
                            .fill(Color(red: 1.0, green: 0.74, blue: 0.18))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                        Circle()
                            .fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                    }
                    .padding(.leading, 12)

                    Spacer()

                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(Color.primary.opacity(0.85))

                    Spacer()

                    Color.clear
                        .frame(width: 50, height: 12)
                }
                .frame(height: 38)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                // Content
                content
                    .frame(width: width, height: height - 38)
            }
            .frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
            )
            .padding(24) // padding for shadow
            .background(Color.clear)
        }
    }

    public struct ShowcaseLibraryView: View {
        let apps: [AndroidAppInfo]

        public var body: some View {
            VStack(spacing: 0) {
                // Top controls bar
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text("Search apps or package names…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                    .frame(maxWidth: 280)

                    HStack(spacing: 6) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 12))
                        Text("Native Window")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.square.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("System Apps")
                            .font(.system(size: 12))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.app")
                            Text("Install APK")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))

                        HStack(spacing: 5) {
                            Image(systemName: "bag")
                            Text("Play Store")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                // App Grid (using standard Grid so ImageRenderer renders all items without scrollview viewport dependency)
                let chunkedApps = stride(from: 0, to: apps.count, by: 2).map {
                    Array(apps[$0..<min($0 + 2, apps.count)])
                }

                VStack(spacing: 12) {
                    ForEach(chunkedApps, id: \.self) { pair in
                        HStack(spacing: 14) {
                            ForEach(pair) { app in
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Text(String(app.displayName.prefix(1)).uppercased())
                                                .font(.title3.weight(.bold))
                                                .foregroundStyle(Color.accentColor)
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(app.displayName)
                                                .font(.system(size: 13, weight: .medium))
                                                .lineLimit(1)
                                            if app.hasMacLauncher {
                                                Image(systemName: "app.badge.checkmark")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Text(app.packageName)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("Open")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(.white)
                                }
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                            }
                            if pair.count == 1 {
                                Spacer()
                            }
                        }
                    }
                }
                .padding(20)
                Spacer()
            }
        }
    }

    public struct ShowcaseSettingsView: View {
        public var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Virtual Machine Hardware")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        settingsRow(label: "CPU Cores", value: "5 cores (Apple M1 Pro)")
                        Divider()
                        settingsRow(label: "Memory (RAM)", value: "4 GB Unified Memory")
                        Divider()
                        settingsRow(label: "GPU Acceleration", value: "Apple Metal (Hardware · 60 FPS)")
                        Divider()
                        settingsToggleRow(label: "Quick Boot Snapshots", subtitle: "Resumes in ~1.8 seconds from snapshot", isOn: true)
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Native Window & Gaming")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        settingsRow(label: "Frame Rate Limit", value: "60 FPS (Smooth)")
                        Divider()
                        settingsToggleRow(label: "CoreAudio Forwarding", subtitle: "Low-latency audio streaming", isOn: true)
                        Divider()
                        settingsToggleRow(label: "VideoToolbox Hardware Decode", subtitle: "Zero CPU decode overhead", isOn: true)
                        Divider()
                        settingsToggleRow(label: "Dynamic Reflow Resize (Flex Display)", subtitle: "Off (2x Retina scale) · On (dynamic window reflow)", isOn: false)
                        Divider()
                        settingsToggleRow(label: "Game Controller Forwarding", subtitle: "PS5 / Xbox wireless controllers via Linux UHID", isOn: true)
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Security & Isolation")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        settingsRow(label: "Hypervisor", value: "Apple Hypervisor.framework (Unprivileged User Space)")
                        Divider()
                        settingsRow(label: "Host Isolation", value: "Isolated — Explicit /sdcard/Download transfer only")
                        Divider()
                        settingsRow(label: "ADB Binding", value: "127.0.0.1 Loopback (emulator-5554)")
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                }

                Spacer()
            }
            .padding(20)
        }

        private func settingsRow(label: String, value: String) -> some View {
            HStack {
                Text(label).font(.body)
                Spacer()
                Text(value).font(.body).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }

        private func settingsToggleRow(label: String, subtitle: String, isOn: Bool) -> some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.body)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    struct ControlCenterContainer<Detail: View>: View {
        let activeTab: SidebarTab
        let detail: Detail

        init(activeTab: SidebarTab, @ViewBuilder detail: () -> Detail) {
            self.activeTab = activeTab
            self.detail = detail()
        }

        public var body: some View {
            HStack(spacing: 0) {
                // Sidebar
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(SidebarTab.allCases) { tab in
                            HStack(spacing: 8) {
                                Image(systemName: tab.symbol)
                                    .frame(width: 18)
                                    .foregroundStyle(activeTab == tab ? Color.white : Color.primary.opacity(0.85))
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: activeTab == tab ? .semibold : .regular))
                                    .foregroundStyle(activeTab == tab ? Color.white : Color.primary.opacity(0.85))
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                activeTab == tab ? Color.accentColor : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 14)

                    Spacer()

                    Divider()

                    // Engine footer
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Running · Android 15")
                                .font(.caption.weight(.medium))
                        }
                        Text("5 cores · 4 GB RAM · Metal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 220)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    public static func saveViewAsPNG<V: View>(_ view: V, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0 // Crisp 2x Retina
        guard let cgImage = renderer.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try pngData.write(to: url, options: .atomic)
            return true
        } catch {
            print("Failed to save \(url.path): \(error)")
            return false
        }
    }

    public static func captureAll(state: AppState, to outputDir: URL) async {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let apps: [AndroidAppInfo] = [
            AndroidAppInfo(packageName: "com.android.settings", displayName: "Settings", isSystemApp: true, hasMacLauncher: true),
            AndroidAppInfo(packageName: "com.android.vending", displayName: "Google Play Store", isSystemApp: true, hasMacLauncher: true),
            AndroidAppInfo(packageName: "com.android.chrome", displayName: "Chrome", isSystemApp: true, hasMacLauncher: false),
            AndroidAppInfo(packageName: "com.google.android.youtube", displayName: "YouTube", isSystemApp: true, hasMacLauncher: false),
            AndroidAppInfo(packageName: "com.google.android.apps.photos", displayName: "Photos", isSystemApp: true, hasMacLauncher: false),
            AndroidAppInfo(packageName: "com.google.android.deskclock", displayName: "Clock", isSystemApp: true, hasMacLauncher: false),
            AndroidAppInfo(packageName: "com.google.android.gm", displayName: "Gmail", isSystemApp: true, hasMacLauncher: false),
            AndroidAppInfo(packageName: "com.google.android.apps.maps", displayName: "Maps", isSystemApp: true, hasMacLauncher: false),
            AndroidAppInfo(packageName: "com.google.android.documentsui", displayName: "Files", isSystemApp: true, hasMacLauncher: false),
            AndroidAppInfo(packageName: "com.google.android.calculator", displayName: "Calculator", isSystemApp: true, hasMacLauncher: false)
        ]

        // 1. Library View
        let libraryWindow = WindowChrome(title: "DroidMac — Control Center", width: 980, height: 640) {
            ControlCenterContainer(activeTab: .library) {
                ShowcaseLibraryView(apps: apps)
            }
        }
        let libURL = outputDir.appendingPathComponent("droidmac-library.png")
        _ = saveViewAsPNG(libraryWindow, to: libURL)
        print("Generated: \(libURL.path)")

        // 2. Settings View
        let settingsWindow = WindowChrome(title: "DroidMac — Performance & Safety", width: 980, height: 640) {
            ControlCenterContainer(activeTab: .settings) {
                ShowcaseSettingsView()
            }
        }
        let setURL = outputDir.appendingPathComponent("droidmac-settings.png")
        _ = saveViewAsPNG(settingsWindow, to: setURL)
        print("Generated: \(setURL.path)")

        // 3. Android Settings App Native Window
        let scratchDir = URL(fileURLWithPath: "/Users/sinarahmannejad/.gemini/antigravity/brain/e8037c7e-9f0f-43ca-8e5f-54a38bd24402/scratch")
        let settingsImgURL = scratchDir.appendingPathComponent("verify_settings.png")
        if let nsImage = NSImage(contentsOf: settingsImgURL) {
            let nativeSettingsWindow = WindowChrome(title: "Settings", width: 440, height: 680) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            let outSettings = outputDir.appendingPathComponent("native-app-settings.png")
            _ = saveViewAsPNG(nativeSettingsWindow, to: outSettings)
            print("Generated: \(outSettings.path)")
        }

        // 4. Android Google Play Store App Native Window
        let playStoreImgURL = scratchDir.appendingPathComponent("playstore_raw.png")
        if let nsImage = NSImage(contentsOf: playStoreImgURL) {
            let nativePlayWindow = WindowChrome(title: "Google Play Store", width: 840, height: 490) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            let outPlay = outputDir.appendingPathComponent("native-app-playstore.png")
            _ = saveViewAsPNG(nativePlayWindow, to: outPlay)
            print("Generated: \(outPlay.path)")
        }

        // 5. Hero Banner: DroidMac Control Center + Native Android Window side by side
        let heroBanner = HStack(spacing: -80) {
            WindowChrome(title: "DroidMac", width: 860, height: 560) {
                ControlCenterContainer(activeTab: .library) {
                    ShowcaseLibraryView(apps: apps)
                }
            }
            .scaleEffect(0.92)

            if let nsImage = NSImage(contentsOf: settingsImgURL) {
                WindowChrome(title: "Settings", width: 380, height: 580) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 30, x: -10, y: 15)
            }
        }
        .padding(40)
        let heroURL = outputDir.appendingPathComponent("droidmac-hero.png")
        _ = saveViewAsPNG(heroBanner, to: heroURL)
        print("Generated: \(heroURL.path)")
    }
}
