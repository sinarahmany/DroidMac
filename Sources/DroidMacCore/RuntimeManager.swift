import Foundation

public final class RuntimeManager: Sendable {
    public let paths: DroidMacPaths
    public let runner: ProcessRunner

    public init(paths: DroidMacPaths = DroidMacPaths(), runner: ProcessRunner = ProcessRunner()) {
        self.paths = paths
        self.runner = runner
    }

    public func inspectStatus(config: EngineConfig) -> RuntimeStatus {
        let fm = FileManager.default
        let javaHome = paths.resolveJavaHome()
        let sdkManager = paths.resolveExecutable("sdkmanager")
        let avdManager = paths.resolveExecutable("avdmanager")
        let adb = paths.resolveExecutable("adb")
        let emulator = paths.resolveExecutable("emulator")
        let scrcpy = paths.resolveExecutable("scrcpy")

        let imageDir = paths.systemImageDirectory(for: config.systemImage)
        let imageInstalled = fm.fileExists(atPath: imageDir.appendingPathComponent("system.img").path)
            || fm.fileExists(atPath: imageDir.appendingPathComponent("source.properties").path)

        let avdIni = paths.avdHome.appendingPathComponent("\(config.avdName).ini")
        let avdConfig = paths.avdConfigINI(named: config.avdName)
        let avdExists = fm.fileExists(atPath: avdIni.path) && fm.fileExists(atPath: avdConfig.path)

        return RuntimeStatus(
            javaPath: javaHome,
            sdkManagerPath: sdkManager,
            avdManagerPath: avdManager,
            adbPath: adb,
            emulatorPath: emulator,
            scrcpyPath: scrcpy,
            systemImageInstalled: imageInstalled,
            avdExists: avdExists,
            architecture: DroidMacPaths.hostArchitecture
        )
    }

    /// Installs Android SDK packages (emulator, platform-tools, ARM64 system image) and creates/optimizes the AVD.
    public func setupRuntime(
        config: EngineConfig,
        onLog: @escaping @Sendable (LogEntry) -> Void
    ) async throws {
        guard Validator.isValidAVDName(config.avdName) else {
            throw DroidMacError.invalidAVDName(config.avdName)
        }
        try paths.ensureDirectoriesExist()

        let status = inspectStatus(config: config)
        guard let sdkManager = status.sdkManagerPath else {
            throw DroidMacError.missingDependency("sdkmanager (install via: brew install --cask android-commandlinetools)")
        }
        guard let avdManager = status.avdManagerPath else {
            throw DroidMacError.missingDependency("avdmanager")
        }
        guard status.javaPath != nil else {
            throw DroidMacError.missingDependency("OpenJDK 21 (install via: brew install openjdk@21)")
        }

        let env = paths.buildEnvironment()

        // Step 1: Ensure cmdline-tools, platform-tools, platforms;android-35, emulator, and ARM64 system image are installed
        let localAvdManager = paths.sdkRoot.appendingPathComponent("cmdline-tools/latest/bin/avdmanager").path
        let hasLocalCmdlineTools = FileManager.default.isExecutableFile(atPath: localAvdManager)
        if status.emulatorPath == nil || !status.systemImageInstalled || !hasLocalCmdlineTools {
            onLog(LogEntry(source: "Setup", message: "Installing Android SDK tools, Emulator & \(config.systemImage.displayName)…"))
            let yesInput = Data(Array(repeating: "y\n", count: 40).joined().utf8)
            let exitCode = try await runner.runStreaming(
                executablePath: sdkManager,
                arguments: [
                    "--sdk_root=\(paths.sdkRoot.path)",
                    "cmdline-tools;latest",
                    "platform-tools",
                    "platforms;android-35",
                    "emulator",
                    config.systemImage.rawValue
                ],
                environment: env,
                standardInput: yesInput
            ) { line, isErr in
                let isNoise = line.hasPrefix("License ") || line.contains("Terms and Conditions") || line.hasPrefix("Accept?")
                if !isNoise {
                    onLog(LogEntry(level: isErr ? .debug : .info, source: "sdkmanager", message: line))
                }
            }
            guard exitCode == 0 else {
                throw DroidMacError.commandFailed(command: "sdkmanager", exitCode: exitCode, stderr: "Failed to install Android SDK components.")
            }
        }

        // Step 2: Create AVD if not present (re-resolve avdmanager from isolated sdkRoot so it sees our system-images)
        let updated = inspectStatus(config: config)
        let resolvedAvdManager = updated.avdManagerPath ?? avdManager
        if !updated.avdExists {
            onLog(LogEntry(source: "Setup", message: "Creating Apple Silicon virtual device '\(config.avdName)'…"))
            let noInput = Data("no\n".utf8)
            let args = [
                "create", "avd",
                "--force",
                "--name", config.avdName,
                "--package", config.systemImage.rawValue,
                "--device", "pixel_7"
            ]
            let result = try await runner.run(
                executablePath: resolvedAvdManager,
                arguments: args,
                environment: env,
                standardInput: noInput,
                timeoutSeconds: 120
            )
            if !result.succeeded {
                // Retry without --device profile in case device definition name differs across cmdline-tools releases
                let fallbackArgs = [
                    "create", "avd",
                    "--force",
                    "--name", config.avdName,
                    "--package", config.systemImage.rawValue
                ]
                let fallback = try await runner.run(
                    executablePath: resolvedAvdManager,
                    arguments: fallbackArgs,
                    environment: env,
                    standardInput: noInput,
                    timeoutSeconds: 120
                )
                guard fallback.succeeded else {
                    throw DroidMacError.commandFailed(command: "avdmanager", exitCode: fallback.exitCode, stderr: fallback.stderr)
                }
            }
        }

        // Step 3: Patch AVD config.ini and advancedFeatures.ini for optimal Apple Silicon + Metal performance
        onLog(LogEntry(source: "Setup", message: "Optimizing AVD configuration for Apple Silicon + Metal GPU…"))
        try applyAVDOptimizations(config: config)
        try ensureAdvancedFeaturesINI()

        onLog(LogEntry(source: "Setup", message: "Runtime ready: \(config.avdName)"))
    }

    public func applyAVDOptimizations(config: EngineConfig) throws {
        let configURL = paths.avdConfigINI(named: config.avdName)
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw DroidMacError.missingDependency("AVD config.ini for \(config.avdName)")
        }
        let existing = try String(contentsOf: configURL, encoding: .utf8)
        let patched = Self.patchAVDConfigINI(existing, config: config)
        try patched.write(to: configURL, atomically: true, encoding: .utf8)
    }

    public static func patchAVDConfigINI(_ original: String, config: EngineConfig) -> String {
        let overrides: [(String, String)] = [
            ("hw.cpu.ncore", "\(config.cpuCores)"),
            ("hw.ramSize", "\(config.ramMB)"),
            ("vm.heapSize", "\(min(max(config.ramMB / 4, 512), 1024))"),
            ("disk.dataPartition.size", "\(config.diskSizeMB)M"),
            ("hw.gpu.enabled", "yes"),
            ("hw.gpu.mode", config.gpuMode.rawValue),
            ("hw.keyboard", "yes"),
            ("hw.audioInput", "yes"),
            ("hw.audioOutput", "yes"),
            ("hw.lcd.width", "1080"),
            ("hw.lcd.height", "2400"),
            ("hw.lcd.density", "420"),
            ("fastboot.forceFastBoot", config.enableQuickBoot ? "yes" : "no"),
            ("fastboot.forceColdBoot", config.enableQuickBoot ? "no" : "yes"),
            ("PlayStore.enabled", config.systemImage.includesPlayStore ? "true" : "false"),
            ("showDeviceFrame", "no")
        ]

        var lines = original.components(separatedBy: .newlines)
        var seenKeys = Set<String>()

        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            if let match = overrides.first(where: { $0.0 == key }) {
                lines[i] = "\(match.0) = \(match.1)"
                seenKeys.insert(key)
            }
        }

        for (key, value) in overrides where !seenKeys.contains(key) {
            lines.append("\(key) = \(value)")
        }

        return lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n") + "\n"
    }

    public func ensureAdvancedFeaturesINI() throws {
        let fm = FileManager.default
        let dotAndroid = fm.homeDirectoryForCurrentUser.appendingPathComponent(".android", isDirectory: true)
        try fm.createDirectory(at: dotAndroid, withIntermediateDirectories: true)
        let iniURL = dotAndroid.appendingPathComponent("advancedFeatures.ini")

        let existing = (try? String(contentsOf: iniURL, encoding: .utf8)) ?? ""
        var lines = existing.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let desired: [(String, String)] = [
            ("Vulkan", "on"),
            ("GLDirectMem", "on"),
            ("HostComposition", "on"),
            ("RefCountPipe", "on"),
            ("VirtioInput", "on")
        ]

        var present = Set<String>()
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if let eq = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                if let match = desired.first(where: { $0.0 == key }) {
                    lines[i] = "\(match.0) = \(match.1)"
                    present.insert(key)
                }
            }
        }

        for (key, value) in desired where !present.contains(key) {
            lines.append("\(key) = \(value)")
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: iniURL, atomically: true, encoding: .utf8)
    }
}
