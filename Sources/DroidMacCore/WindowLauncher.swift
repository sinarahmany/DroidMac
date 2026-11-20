import Foundation

public actor WindowLauncher {
    public let paths: DroidMacPaths
    public let runner: ProcessRunner

    private var activeProcesses: [UUID: (process: Process, session: ActiveWindowSession)] = [:]

    public init(paths: DroidMacPaths = DroidMacPaths(), runner: ProcessRunner = ProcessRunner()) {
        self.paths = paths
        self.runner = runner
    }

    public static func buildAppWindowArguments(
        serial: String,
        packageName: String,
        windowTitle: String,
        profile: LaunchProfile,
        config: EngineConfig
    ) -> [String] {
        var args: [String] = [
            "-s", serial,
            "--new-display=\(profile.virtualDisplaySpec)",
            "--start-app=+\(packageName)",
            "--window-title=\(windowTitle)",
            "--max-fps=\(max(15, min(120, config.maxFPS)))",
            "--video-bit-rate=\(profile.defaultBitrateMbps)M",
            "--render-driver=metal"
        ]

        if profile.supportsFlexDisplay {
            // scrcpy 5.x forbids --window-width/--window-height when --flex-display is set
            args.append("--flex-display")
        } else {
            args.append(contentsOf: [
                "--window-width=\(profile.defaultWindowWidth)",
                "--window-height=\(profile.defaultWindowHeight)"
            ])
        }

        if config.enableHardwareDecode {
            args.append("--hwdec=videotoolbox")
        }

        if config.hideSystemDecorationsInAppMode && profile == .adaptiveApp {
            args.append("--no-vd-system-decorations")
        }

        if config.enableAudio {
            args.append("--audio-buffer=40")
        } else {
            args.append("--no-audio")
        }

        if config.enableGamepad && profile == .gameLandscape {
            args.append("--gamepad=uhid")
        }

        return args
    }

    public static func buildFullDeviceArguments(
        serial: String,
        windowTitle: String,
        config: EngineConfig
    ) -> [String] {
        var args: [String] = [
            "-s", serial,
            "--window-title=\(windowTitle)",
            "--max-fps=\(max(15, min(120, config.maxFPS)))",
            "--video-bit-rate=12M",
            "--render-driver=metal"
        ]
        if config.enableHardwareDecode {
            args.append("--hwdec=videotoolbox")
        }
        if config.enableAudio {
            args.append("--audio-buffer=40")
        } else {
            args.append("--no-audio")
        }
        if config.enableGamepad {
            args.append("--gamepad=uhid")
        }
        return args
    }

    public func listActiveSessions() -> [ActiveWindowSession] {
        activeProcesses.values
            .filter { $0.process.isRunning }
            .map(\.session)
            .sorted { $0.startedAt < $1.startedAt }
    }

    public func launchAppWindow(
        serial: String,
        packageName: String,
        windowTitle: String,
        profile: LaunchProfile,
        config: EngineConfig,
        onLog: (@Sendable (LogEntry) -> Void)? = nil,
        onWindowClosed: (@Sendable (UUID) -> Void)? = nil
    ) throws -> ActiveWindowSession {
        guard Validator.isValidPackageName(packageName) else {
            throw DroidMacError.invalidPackageName(packageName)
        }
        guard let scrcpyPath = paths.resolveExecutable("scrcpy") else {
            throw DroidMacError.missingDependency("scrcpy")
        }

        let args = Self.buildAppWindowArguments(
            serial: serial,
            packageName: packageName,
            windowTitle: windowTitle,
            profile: profile,
            config: config
        )

        return try spawnWindow(
            scrcpyPath: scrcpyPath,
            arguments: args,
            packageName: packageName,
            title: windowTitle,
            profile: profile,
            onLog: onLog,
            onWindowClosed: onWindowClosed
        )
    }

    public func launchFullDeviceWindow(
        serial: String,
        windowTitle: String = "DroidMac · Android 15",
        config: EngineConfig,
        onLog: (@Sendable (LogEntry) -> Void)? = nil,
        onWindowClosed: (@Sendable (UUID) -> Void)? = nil
    ) throws -> ActiveWindowSession {
        guard let scrcpyPath = paths.resolveExecutable("scrcpy") else {
            throw DroidMacError.missingDependency("scrcpy")
        }

        let args = Self.buildFullDeviceArguments(
            serial: serial,
            windowTitle: windowTitle,
            config: config
        )

        return try spawnWindow(
            scrcpyPath: scrcpyPath,
            arguments: args,
            packageName: nil,
            title: windowTitle,
            profile: nil,
            onLog: onLog,
            onWindowClosed: onWindowClosed
        )
    }

    private func spawnWindow(
        scrcpyPath: String,
        arguments: [String],
        packageName: String?,
        title: String,
        profile: LaunchProfile?,
        onLog: (@Sendable (LogEntry) -> Void)?,
        onWindowClosed: (@Sendable (UUID) -> Void)?
    ) throws -> ActiveWindowSession {
        let sessionID = UUID()
        onLog?(LogEntry(source: "Window", message: "Opening native window '\(title)'…"))

        let process = try runner.spawn(
            executablePath: scrcpyPath,
            arguments: arguments,
            environment: paths.buildEnvironment(),
            onLine: { line, isErr in
                let isErrLine = isErr && (line.contains("ERROR:") || line.contains("FATAL:"))
                onLog?(LogEntry(level: isErrLine ? .error : .debug, source: "scrcpy[\(title)]", message: line))
            },
            onExit: { [weak self] code in
                onLog?(LogEntry(
                    level: code == 0 ? .info : .warning,
                    source: "Window",
                    message: "Window '\(title)' closed (exit \(code))."
                ))
                Task { await self?.removeSession(sessionID) }
                onWindowClosed?(sessionID)
            }
        )

        let session = ActiveWindowSession(
            id: sessionID,
            packageName: packageName,
            title: title,
            profile: profile,
            pid: process.processIdentifier
        )
        activeProcesses[sessionID] = (process, session)
        return session
    }

    private func removeSession(_ id: UUID) {
        activeProcesses.removeValue(forKey: id)
    }

    public func closeWindow(id: UUID) {
        guard let entry = activeProcesses.removeValue(forKey: id) else { return }
        if entry.process.isRunning {
            entry.process.terminate()
        }
    }

    public func closeAllWindows() {
        let entries = activeProcesses.values
        activeProcesses.removeAll()
        for entry in entries where entry.process.isRunning {
            entry.process.terminate()
        }
    }
}
