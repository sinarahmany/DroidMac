import Foundation

public actor EmulatorEngine {
    public let paths: DroidMacPaths
    public let runner: ProcessRunner
    public let runtimeManager: RuntimeManager

    private var process: Process?
    private var detectedFallbackToSoftwareGPU = false

    public init(
        paths: DroidMacPaths = DroidMacPaths(),
        runner: ProcessRunner = ProcessRunner(),
        runtimeManager: RuntimeManager? = nil
    ) {
        self.paths = paths
        self.runner = runner
        self.runtimeManager = runtimeManager ?? RuntimeManager(paths: paths, runner: runner)
    }

    public static func buildEmulatorArguments(config: EngineConfig) -> [String] {
        var args = [
            "-avd", config.avdName,
            "-no-window",
            "-gpu", config.gpuMode.rawValue,
            "-cores", "\(max(2, config.cpuCores))",
            "-memory", "\(max(2048, config.ramMB))",
            "-port", "\(config.port)",
            "-no-boot-anim",
            "-no-metrics",
            "-netdelay", "none",
            "-netspeed", "full",
            "-grpc-use-token"
        ]
        if !config.enableQuickBoot {
            args.append(contentsOf: ["-no-snapshot-load", "-no-snapshot-save"])
        }
        return args
    }

    public func isEmulatorOnline(serial: String) async -> Bool {
        guard let adb = paths.resolveExecutable("adb") else { return false }
        guard let result = try? await runner.run(
            executablePath: adb,
            arguments: ["devices"],
            environment: paths.buildEnvironment(),
            timeoutSeconds: 10
        ) else { return false }

        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2 && parts[0] == serial && parts[1] == "device" {
                return true
            }
        }
        return false
    }

    public func isBootCompleted(serial: String) async -> Bool {
        guard let adb = paths.resolveExecutable("adb") else { return false }
        guard let result = try? await runner.run(
            executablePath: adb,
            arguments: ["-s", serial, "shell", "getprop", "sys.boot_completed"],
            environment: paths.buildEnvironment(),
            timeoutSeconds: 10
        ), result.succeeded else { return false }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    public func queryAndroidVersion(serial: String) async -> String {
        guard let adb = paths.resolveExecutable("adb") else { return "15" }
        guard let result = try? await runner.run(
            executablePath: adb,
            arguments: ["-s", serial, "shell", "getprop", "ro.build.version.release"],
            environment: paths.buildEnvironment(),
            timeoutSeconds: 10
        ), result.succeeded else { return "15" }
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? "15" : version
    }

    public func queryActiveGPURenderer(serial: String) async -> String {
        guard let adb = paths.resolveExecutable("adb") else { return "Unknown" }
        guard let result = try? await runner.run(
            executablePath: adb,
            arguments: ["-s", serial, "shell", "dumpsys", "SurfaceFlinger"],
            environment: paths.buildEnvironment(),
            timeoutSeconds: 10
        ), result.succeeded else {
            return detectedFallbackToSoftwareGPU ? "Software Fallback" : "Apple Metal (Host)"
        }
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            if line.contains("GLES:") || line.contains("Vulkan") {
                return line.trimmingCharacters(in: .whitespaces)
            }
        }
        return detectedFallbackToSoftwareGPU ? "Software Fallback" : "Apple Metal (Host)"
    }

    /// Starts the headless ARM64 Android VM (or attaches if already running) and prepares multi-display support.
    public func start(
        config: EngineConfig,
        detached: Bool = false,
        onStatus: @escaping @Sendable (String) -> Void,
        onLog: @escaping @Sendable (LogEntry) -> Void,
        onUnexpectedExit: (@Sendable (Int32) -> Void)? = nil
    ) async throws -> (serial: String, androidVersion: String, gpuActive: String) {
        let serial = config.emulatorSerial
        let status = runtimeManager.inspectStatus(config: config)
        guard let emulatorPath = status.emulatorPath else {
            throw DroidMacError.missingDependency("Android Emulator")
        }
        guard let adbPath = status.adbPath else {
            throw DroidMacError.missingDependency("adb")
        }
        guard status.avdExists else {
            throw DroidMacError.missingDependency("AVD '\(config.avdName)'")
        }

        // Attach immediately if already running and booted
        if await isEmulatorOnline(serial: serial), await isBootCompleted(serial: serial) {
            onLog(LogEntry(source: "Engine", message: "Attached to running headless Android VM (\(serial))."))
            await configureMultiDisplaySettings(adbPath: adbPath, serial: serial, onLog: onLog)
            let version = await queryAndroidVersion(serial: serial)
            let gpu = await queryActiveGPURenderer(serial: serial)
            return (serial, version, gpu)
        }

        try runtimeManager.applyAVDOptimizations(config: config)
        try runtimeManager.ensureAdvancedFeaturesINI()

        detectedFallbackToSoftwareGPU = false
        let args = Self.buildEmulatorArguments(config: config)
        let env = paths.buildEnvironment()

        onStatus("Booting ARM64 Android VM…")
        onLog(LogEntry(source: "Engine", message: "Starting headless VM: \(config.avdName) (\(config.cpuCores) cores, \(config.ramMB) MB RAM, GPU: \(config.gpuMode.rawValue))"))

        let spawned: Process
        if detached {
            let logURL = paths.appSupportDir.appendingPathComponent("emulator.log")
            spawned = try runner.spawnDetached(
                executablePath: emulatorPath,
                arguments: args,
                environment: env,
                logFileURL: logURL
            )
            onLog(LogEntry(source: "Engine", message: "Detached VM logs: \(logURL.path)"))
        } else {
            spawned = try runner.spawn(
                executablePath: emulatorPath,
                arguments: args,
                environment: env,
                onLine: { [weak self] line, isErr in
                    let lower = line.lowercased()
                    let isWarning = lower.contains("warn") || lower.contains("switching to software")
                    let level: LogLevel = isWarning ? .warning : (isErr ? .debug : .info)
                    onLog(LogEntry(level: level, source: "emulator", message: line))
                    if lower.contains("switching to software rendering") {
                        Task { await self?.markSoftwareGPUFallback() }
                    }
                },
                onExit: { code in
                    onLog(LogEntry(
                        level: code == 0 ? .info : .warning,
                        source: "Engine",
                        message: "Emulator process exited with status \(code)."
                    ))
                    onUnexpectedExit?(code)
                }
            )
        }
        self.process = spawned

        // Poll until adb sees emulator & sys.boot_completed == 1 (max 150s for cold first boot)
        let deadline = Date().addingTimeInterval(150)
        var sawDevice = false
        while Date() < deadline {
            if !spawned.isRunning {
                throw DroidMacError.commandFailed(
                    command: "emulator",
                    exitCode: spawned.terminationStatus,
                    stderr: "Emulator exited prematurely before completing boot. Check Diagnostics Logs."
                )
            }
            if !sawDevice {
                if await isEmulatorOnline(serial: serial) {
                    sawDevice = true
                    onStatus("Waiting for Android OS services…")
                    onLog(LogEntry(source: "Engine", message: "ADB connected to \(serial); waiting for boot completion…"))
                }
            }
            if sawDevice, await isBootCompleted(serial: serial) {
                onStatus("Configuring native multi-display…")
                await configureMultiDisplaySettings(adbPath: adbPath, serial: serial, onLog: onLog)
                let version = await queryAndroidVersion(serial: serial)
                let gpu = await queryActiveGPURenderer(serial: serial)
                onLog(LogEntry(source: "Engine", message: "Android \(version) booted successfully. GPU: \(gpu)"))
                return (serial, version, gpu)
            }
            try await Task.sleep(for: .seconds(1))
        }

        await stop(serial: serial, onLog: onLog)
        throw DroidMacError.emulatorBootTimeout
    }

    private func markSoftwareGPUFallback() {
        detectedFallbackToSoftwareGPU = true
    }

    private func configureMultiDisplaySettings(
        adbPath: String,
        serial: String,
        onLog: @escaping @Sendable (LogEntry) -> Void
    ) async {
        let env = paths.buildEnvironment()
        let settings: [(String, String)] = [
            ("enable_freeform_support", "1"),
            ("force_resizable_activities", "1"),
            ("stay_on_while_plugged_in", "3"),
            ("enable_non_resizable_multi_window", "1")
        ]
        for (key, value) in settings {
            _ = try? await runner.run(
                executablePath: adbPath,
                arguments: ["-s", serial, "shell", "settings", "put", "global", key, value],
                environment: env,
                timeoutSeconds: 10
            )
        }
        // Dismiss lock screen / keyguard so apps launch cleanly without swipe barrier
        _ = try? await runner.run(
            executablePath: adbPath,
            arguments: ["-s", serial, "shell", "wm", "dismiss-keyguard"],
            environment: env,
            timeoutSeconds: 10
        )
        onLog(LogEntry(source: "Engine", message: "Enabled Android freeform & multi-display support."))
    }

    /// Gracefully shuts down the emulator so Quick Boot snapshots save cleanly and zero orphan QEMU processes remain.
    public func stop(
        serial: String,
        onLog: (@Sendable (LogEntry) -> Void)? = nil
    ) async {
        onLog?(LogEntry(source: "Engine", message: "Shutting down Android VM (\(serial)) gracefully…"))

        if let adb = paths.resolveExecutable("adb") {
            _ = try? await runner.run(
                executablePath: adb,
                arguments: ["-s", serial, "emu", "kill"],
                environment: paths.buildEnvironment(),
                timeoutSeconds: 10
            )
        }

        // Wait up to 8 seconds for graceful snapshot save & exit
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let stillManagedRunning = process?.isRunning ?? false
            let stillOnline = await isEmulatorOnline(serial: serial)
            if !stillManagedRunning && !stillOnline {
                process = nil
                onLog?(LogEntry(source: "Engine", message: "Android VM stopped cleanly."))
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
        }

        if let proc = process, proc.isRunning {
            onLog?(LogEntry(level: .warning, source: "Engine", message: "Force-terminating lingering emulator process…"))
            proc.terminate()
            try? await Task.sleep(for: .milliseconds(500))
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
        process = nil
    }
}
