import Foundation
import Testing
@testable import DroidMacCore

@Suite("DroidMacCore Unit Tests")
struct DroidMacCoreTests {

    @Test("Package name validator accepts valid names and rejects injection payloads")
    func testPackageValidation() {
        #expect(Validator.isValidPackageName("com.android.settings"))
        #expect(Validator.isValidPackageName("org.mozilla.firefox_beta"))
        #expect(Validator.isValidPackageName("com.supercell.clashroyale"))

        #expect(!Validator.isValidPackageName(""))
        #expect(!Validator.isValidPackageName("singleword"))
        #expect(!Validator.isValidPackageName("com.example; rm -rf /"))
        #expect(!Validator.isValidPackageName("com.example$(whoami)"))
        #expect(!Validator.isValidPackageName("../etc/passwd"))
        #expect(!Validator.isValidPackageName("com.123invalid.app"))
    }

    @Test("AVD name validator rejects unsafe names")
    func testAVDValidation() {
        #expect(Validator.isValidAVDName("DroidMac_ARM64"))
        #expect(Validator.isValidAVDName("Pixel-7.API35"))
        #expect(!Validator.isValidAVDName(""))
        #expect(!Validator.isValidAVDName("bad name with spaces"))
        #expect(!Validator.isValidAVDName("avd;whoami"))
    }

    @Test("APK archive validator checks extension and ZIP magic header")
    func testAPKArchiveValidation() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DroidMacTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let badExt = tmp.appendingPathComponent("malware.sh")
        try Data("#!/bin/sh\n".utf8).write(to: badExt)
        #expect(throws: DroidMacError.self) {
            try Validator.validateAPKArchive(at: badExt)
        }

        let fakeAPK = tmp.appendingPathComponent("fake.apk")
        try Data("NOT_A_ZIP_FILE".utf8).write(to: fakeAPK)
        #expect(throws: DroidMacError.self) {
            try Validator.validateAPKArchive(at: fakeAPK)
        }

        let validHeaderAPK = tmp.appendingPathComponent("valid.apk")
        try Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00]).write(to: validHeaderAPK)
        try Validator.validateAPKArchive(at: validHeaderAPK)
    }

    @Test("AVD config.ini patcher applies Apple Silicon + Metal tuning cleanly")
    func testAVDConfigPatching() {
        let original = """
        AvdId = DroidMac_ARM64
        hw.cpu.ncore = 2
        hw.ramSize = 2048
        hw.gpu.mode = auto
        tag.id = google_apis_playstore
        """

        let config = EngineConfig(
            avdName: "DroidMac_ARM64",
            systemImage: .android35PlayStore,
            cpuCores: 6,
            ramMB: 6144,
            diskSizeMB: 8192,
            gpuMode: .host,
            enableQuickBoot: true
        )

        let patched = RuntimeManager.patchAVDConfigINI(original, config: config)
        #expect(patched.contains("AvdId = DroidMac_ARM64"))
        #expect(patched.contains("tag.id = google_apis_playstore"))
        #expect(patched.contains("hw.cpu.ncore = 6"))
        #expect(patched.contains("hw.ramSize = 6144"))
        #expect(patched.contains("hw.gpu.enabled = yes"))
        #expect(patched.contains("hw.gpu.mode = host"))
        #expect(patched.contains("fastboot.forceFastBoot = yes"))
        #expect(patched.contains("PlayStore.enabled = true"))
    }

    @Test("Emulator arguments enforce headless Metal GPU and snapshot preferences")
    func testEmulatorArguments() {
        let fastConfig = EngineConfig(avdName: "DroidMac_ARM64", cpuCores: 4, ramMB: 4096, gpuMode: .host, enableQuickBoot: true)
        let args = EmulatorEngine.buildEmulatorArguments(config: fastConfig)
        #expect(args.contains("-no-window"))
        #expect(args.contains("-gpu"))
        #expect(args.contains("host"))
        #expect(!args.contains("-no-snapshot-load"))

        var coldConfig = fastConfig
        coldConfig.enableQuickBoot = false
        let coldArgs = EmulatorEngine.buildEmulatorArguments(config: coldConfig)
        #expect(coldArgs.contains("-no-snapshot-load"))
        #expect(coldArgs.contains("-no-snapshot-save"))
    }

    @Test("WindowLauncher builds valid scrcpy 5.0 arguments for App Mode and Game Mode")
    func testWindowLauncherArguments() {
        let config = EngineConfig(maxFPS: 60, enableAudio: true, enableGamepad: true, enableHardwareDecode: true)

        let appArgs = WindowLauncher.buildAppWindowArguments(
            serial: "emulator-5554",
            packageName: "com.android.settings",
            windowTitle: "Settings",
            profile: .adaptiveApp,
            config: config
        )
        #expect(appArgs.contains("--new-display=1080x1560/320"))
        #expect(appArgs.contains("--render-fit=letterbox"))
        #expect(appArgs.contains("--window-width=540"))
        #expect(appArgs.contains("--window-height=780"))
        #expect(!appArgs.contains("--flex-display"))
        #expect(appArgs.contains("--start-app=+com.android.settings"))
        #expect(appArgs.contains("--render-driver=metal"))
        #expect(appArgs.contains("--hwdec=videotoolbox"))
        #expect(!appArgs.contains("--gamepad=uhid"))

        var flexConfig = config
        flexConfig.enableFlexDisplay = true
        let flexArgs = WindowLauncher.buildAppWindowArguments(
            serial: "emulator-5554",
            packageName: "com.android.settings",
            windowTitle: "Settings",
            profile: .adaptiveApp,
            config: flexConfig
        )
        #expect(flexArgs.contains("--new-display=540x780/160"))
        #expect(flexArgs.contains("--flex-display"))
        #expect(flexArgs.contains("--render-fit=letterbox"))
        #expect(!flexArgs.contains(where: { $0.hasPrefix("--window-width=") }))
        #expect(!flexArgs.contains(where: { $0.hasPrefix("--window-height=") }))

        let gameArgs = WindowLauncher.buildAppWindowArguments(
            serial: "emulator-5554",
            packageName: "com.example.racer",
            windowTitle: "Racer 3D",
            profile: .gameLandscape,
            config: flexConfig
        )
        #expect(gameArgs.contains("--new-display=1920x1080/320"))
        #expect(!gameArgs.contains("--flex-display"))
        #expect(gameArgs.contains("--render-fit=letterbox"))
        #expect(gameArgs.contains("--window-width=1152"))
        #expect(gameArgs.contains("--window-height=648"))
        #expect(gameArgs.contains("--video-bit-rate=16M"))
        #expect(gameArgs.contains("--gamepad=uhid"))
    }

    @Test("EngineConfig decodes legacy config JSON without enableFlexDisplay")
    func testEngineConfigBackwardCompatibleDecoding() throws {
        let legacyJSON = """
        {
          "avdName": "DroidMac_ARM64",
          "cpuCores": 6,
          "ramMB": 6144
        }
        """
        let decoded = try JSONDecoder().decode(EngineConfig.self, from: Data(legacyJSON.utf8))
        #expect(decoded.avdName == "DroidMac_ARM64")
        #expect(decoded.cpuCores == 6)
        #expect(decoded.ramMB == 6144)
        #expect(decoded.enableFlexDisplay == false)
        #expect(decoded.gpuMode == .host)
    }

    @Test("scrcpy --list-apps output parser separates user apps and curated system apps")
    func testParseScrcpyApps() {
        let sample = """
         * Settings                         com.android.settings
         * Google Play Store                com.android.vending
         * Internal Carrier Service         com.android.carrierdefaultapp
         - Genshin Impact                   com.miHoYo.GenshinImpact
         - VLC                              org.videolan.vlc
        """
        let paths = DroidMacPaths()
        let filtered = ADBClient.parseScrcpyAppList(sample, includeSystem: false, paths: paths)
        #expect(filtered.count == 4)
        #expect(filtered[0].packageName == "com.miHoYo.GenshinImpact")
        #expect(filtered[1].packageName == "org.videolan.vlc")
        #expect(filtered.contains(where: { $0.packageName == "com.android.vending" }))
        #expect(!filtered.contains(where: { $0.packageName == "com.android.carrierdefaultapp" }))

        let all = ADBClient.parseScrcpyAppList(sample, includeSystem: true, paths: paths)
        #expect(all.count == 5)
    }

    @Test("Icon entry selector prefers highest-density launcher PNG")
    func testIconSelection() {
        let entries = [
            "res/mipmap-hdpi-v4/ic_launcher.png",
            "res/mipmap-xxxhdpi-v4/ic_launcher_background.png",
            "res/mipmap-xxxhdpi-v4/ic_launcher.png",
            "res/mipmap-xhdpi-v4/ic_launcher.webp"
        ]
        #expect(ADBClient.pickBestIconEntry(from: entries) == "res/mipmap-xxxhdpi-v4/ic_launcher.png")
    }

    @Test("MacAppBundleBuilder creates valid .app bundle with Info.plist, .icns, and executable launcher")
    func testMacAppBundleCreation() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DroidMacBundles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let paths = DroidMacPaths(appSupportDir: tmp.appendingPathComponent("support"), launchersDir: tmp.appendingPathComponent("apps"))
        let builder = MacAppBundleBuilder(paths: paths)
        let app = AndroidAppInfo(packageName: "com.android.settings", displayName: "Settings", isSystemApp: true)

        let bundleURL = try await builder.createMacAppBundle(
            for: app,
            profile: .adaptiveApp,
            iconPNGURL: nil,
            cliBinaryPath: "/usr/local/bin/DroidMacCLI"
        )

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: bundleURL.path))
        #expect(fm.fileExists(atPath: bundleURL.appendingPathComponent("Contents/Info.plist").path))
        #expect(fm.fileExists(atPath: bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns").path))
        let execPath = bundleURL.appendingPathComponent("Contents/MacOS/DroidMacLauncher").path
        #expect(fm.isExecutableFile(atPath: execPath))

        let script = try String(contentsOfFile: execPath, encoding: .utf8)
        #expect(script.contains("--package 'com.android.settings'"))
        #expect(script.contains("--profile 'adaptive'"))
    }
}
