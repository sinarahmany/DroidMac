import Foundation
import DroidMacCore

@main
struct DroidMacCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            exit(0)
        }

        let paths = DroidMacPaths()
        let config = EngineConfig.load(from: paths.configURL)
        let runtime = RuntimeManager(paths: paths)
        let engine = EmulatorEngine(paths: paths, runtimeManager: runtime)
        let adb = ADBClient(paths: paths)
        let launcher = WindowLauncher(paths: paths)
        let bundleBuilder = MacAppBundleBuilder(paths: paths)

        do {
            switch command {
            case "status":
                let status = runtime.inspectStatus(config: config)
                let online = await engine.isEmulatorOnline(serial: config.emulatorSerial)
                let booted = online ? await engine.isBootCompleted(serial: config.emulatorSerial) : false
                print("Architecture: \(status.architecture) (Apple Silicon: \(status.isAppleSilicon))")
                print("Ready to boot: \(status.isReadyToBoot)")
                if !status.missingItems.isEmpty {
                    print("Missing: \(status.missingItems.joined(separator: ", "))")
                }
                print("AVD: \(config.avdName)")
                print("VM Online: \(online) (Boot Completed: \(booted))")
                if booted {
                    let version = await engine.queryAndroidVersion(serial: config.emulatorSerial)
                    let gpu = await engine.queryActiveGPURenderer(serial: config.emulatorSerial)
                    print("Android Version: \(version)")
                    print("GPU: \(gpu)")
                }

            case "setup":
                try await runtime.setupRuntime(config: config) { entry in
                    print("[\(entry.source)] \(entry.message)")
                }
                print("Setup completed successfully.")

            case "start":
                let info = try await engine.start(
                    config: config,
                    detached: true,
                    onStatus: { print("[Status] \($0)") },
                    onLog: { entry in
                        if entry.level != .debug {
                            print("[\(entry.level.rawValue)][\(entry.source)] \(entry.message)")
                        }
                    }
                )
                print("Running: \(info.serial) · Android \(info.androidVersion) · \(info.gpuActive)")

            case "stop":
                await engine.stop(serial: config.emulatorSerial) { entry in
                    print("[\(entry.source)] \(entry.message)")
                }

            case "apps":
                let includeSystem = args.contains("--all")
                guard await engine.isBootCompleted(serial: config.emulatorSerial) else {
                    throw DroidMacError.emulatorNotRunning
                }
                let apps = try await adb.listLaunchableApps(serial: config.emulatorSerial, includeSystem: includeSystem)
                for app in apps {
                    let tag = app.isSystemApp ? "system" : "user"
                    let macTag = app.hasMacLauncher ? " [.app]" : ""
                    print("[\(tag)] \(app.displayName) (\(app.packageName))\(macTag)")
                }

            case "install":
                guard let path = args.dropFirst().first else {
                    throw DroidMacError.invalidAPKFile("Please specify a path to an .apk, .xapk, or .apks file.")
                }
                guard await engine.isBootCompleted(serial: config.emulatorSerial) else {
                    throw DroidMacError.emulatorNotRunning
                }
                try await adb.installPackage(serial: config.emulatorSerial, fileURL: URL(fileURLWithPath: path)) { entry in
                    print("[\(entry.source)] \(entry.message)")
                }

            case "launch":
                let packageName = flagValue("--package", in: args)
                let profileRaw = flagValue("--profile", in: args) ?? LaunchProfile.adaptiveApp.rawValue
                let profile = LaunchProfile(rawValue: profileRaw) ?? .adaptiveApp
                let title = flagValue("--title", in: args) ?? packageName.map(ADBClient.fallbackDisplayName) ?? "DroidMac · Android"

                // Ensure headless VM is running & ready before launching window
                let booted = await engine.isBootCompleted(serial: config.emulatorSerial)
                if !booted {
                    _ = try await engine.start(
                        config: config,
                        detached: true,
                        onStatus: { print("[Status] \($0)") },
                        onLog: { entry in
                            if entry.level != .debug {
                                print("[\(entry.source)] \(entry.message)")
                            }
                        }
                    )
                }

                let session: ActiveWindowSession
                if let pkg = packageName {
                    session = try await launcher.launchAppWindow(
                        serial: config.emulatorSerial,
                        packageName: pkg,
                        windowTitle: title,
                        profile: profile,
                        config: config,
                        onLog: { entry in
                            if entry.level != .debug {
                                print("[\(entry.source)] \(entry.message)")
                            }
                        }
                    )
                } else {
                    session = try await launcher.launchFullDeviceWindow(
                        serial: config.emulatorSerial,
                        windowTitle: title,
                        config: config,
                        onLog: { entry in
                            if entry.level != .debug {
                                print("[\(entry.source)] \(entry.message)")
                            }
                        }
                    )
                }

                print("Launched window PID \(session.pid): \(session.title)")
                // Stay alive while the native window is open so Dock/AppKit launcher sessions track cleanly
                while !(await launcher.listActiveSessions()).isEmpty {
                    try? await Task.sleep(for: .milliseconds(500))
                }

            case "wrap":
                guard let pkg = flagValue("--package", in: args) else {
                    throw DroidMacError.invalidPackageName("(missing --package)")
                }
                let name = flagValue("--name", in: args) ?? ADBClient.fallbackDisplayName(for: pkg)
                let profileRaw = flagValue("--profile", in: args) ?? LaunchProfile.adaptiveApp.rawValue
                let profile = LaunchProfile(rawValue: profileRaw) ?? .adaptiveApp

                var iconURL: URL?
                if await engine.isBootCompleted(serial: config.emulatorSerial) {
                    iconURL = await adb.extractAppIcon(serial: config.emulatorSerial, packageName: pkg)
                }
                let appInfo = AndroidAppInfo(packageName: pkg, displayName: name, isSystemApp: false, iconPath: iconURL?.path)
                let created = try await bundleBuilder.createMacAppBundle(for: appInfo, profile: profile, iconPNGURL: iconURL)
                print("Created native macOS app: \(created.path)")

            default:
                printUsage()
                exit(1)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func flagValue(_ flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), args.indices.contains(idx + 1) else {
            return nil
        }
        return args[idx + 1]
    }

    static func printUsage() {
        print("""
        DroidMacCLI — Native macOS Android Emulator Helper

        Commands:
          status                                         Check runtime & headless VM status
          setup                                          Install SDK/AVD runtime and optimize for Apple Silicon
          start                                          Start headless ARM64 Android VM
          stop                                           Gracefully shut down headless Android VM
          apps [--all]                                   List installed Android apps
          install <path.apk|.xapk|.apks>                 Validate & install an Android package
          launch [--package <pkg>] [--profile <mode>] [--title <name>]
                                                         Auto-boot VM if needed & open native macOS window
          wrap --package <pkg> [--name <name>] [--profile <mode>]
                                                         Create a Spotlight/Dock native .app bundle
        """)
    }
}
