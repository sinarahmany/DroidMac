import Foundation

public enum GPUMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case host = "host"
    case swiftshaderIndirect = "swiftshader_indirect"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .host:
            return "Apple Metal (Hardware)"
        case .swiftshaderIndirect:
            return "Software Fallback (CPU)"
        }
    }

    public var subtitle: String {
        switch self {
        case .host:
            return "Uses your Mac GPU via gfxstream + Metal for smooth 60 FPS apps & 3D games."
        case .swiftshaderIndirect:
            return "CPU-based rendering fallback if a specific app has GPU shader issues."
        }
    }
}

public enum SystemImageVariant: String, Codable, CaseIterable, Sendable, Identifiable {
    case android35PlayStore = "system-images;android-35;google_apis_playstore;arm64-v8a"
    case android35GoogleAPIs = "system-images;android-35;google_apis;arm64-v8a"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .android35PlayStore:
            return "Android 15 + Google Play Store (ARM64)"
        case .android35GoogleAPIs:
            return "Android 15 Google APIs (ARM64, Lightweight)"
        }
    }

    public var includesPlayStore: Bool {
        self == .android35PlayStore
    }
}

public enum LaunchProfile: String, Codable, CaseIterable, Sendable, Identifiable {
    case adaptiveApp = "adaptive"
    case gameLandscape = "game"
    case phonePortrait = "phone"
    case tabletLandscape = "tablet"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .adaptiveApp: return "Native Window"
        case .gameLandscape: return "Game (1080p)"
        case .phonePortrait: return "Phone"
        case .tabletLandscape: return "Tablet"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .adaptiveApp: return "macwindow"
        case .gameLandscape: return "gamecontroller"
        case .phonePortrait: return "iphone"
        case .tabletLandscape: return "ipad.landscape"
        }
    }

    public var virtualDisplaySpec: String {
        switch self {
        case .adaptiveApp: return "1080x1560/320"
        case .gameLandscape: return "1920x1080/320"
        case .phonePortrait: return "1080x2340/420"
        case .tabletLandscape: return "1920x1200/300"
        }
    }

    public var flexVirtualDisplaySpec: String {
        switch self {
        case .adaptiveApp: return "540x780/160"
        case .gameLandscape: return "1920x1080/320"
        case .phonePortrait: return "412x820/160"
        case .tabletLandscape: return "960x600/160"
        }
    }

    public var supportsFlexDisplay: Bool {
        switch self {
        case .adaptiveApp, .tabletLandscape, .phonePortrait:
            return true
        case .gameLandscape:
            return false
        }
    }

    public var defaultWindowWidth: Int {
        switch self {
        case .adaptiveApp: return 540
        case .gameLandscape: return 1152
        case .phonePortrait: return 380
        case .tabletLandscape: return 960
        }
    }

    public var defaultWindowHeight: Int {
        switch self {
        case .adaptiveApp: return 780
        case .gameLandscape: return 648
        case .phonePortrait: return 824
        case .tabletLandscape: return 600
        }
    }

    public var defaultBitrateMbps: Int {
        switch self {
        case .gameLandscape: return 16
        case .tabletLandscape: return 12
        case .adaptiveApp, .phonePortrait: return 8
        }
    }
}

public struct EngineConfig: Codable, Equatable, Sendable {
    public var avdName: String
    public var systemImage: SystemImageVariant
    public var cpuCores: Int
    public var ramMB: Int
    public var diskSizeMB: Int
    public var gpuMode: GPUMode
    public var maxFPS: Int
    public var enableAudio: Bool
    public var enableGamepad: Bool
    public var enableQuickBoot: Bool
    public var enableHardwareDecode: Bool
    public var enableFlexDisplay: Bool
    public var hideSystemDecorationsInAppMode: Bool
    public var port: Int

    public init(
        avdName: String = "DroidMac_ARM64",
        systemImage: SystemImageVariant = .android35PlayStore,
        cpuCores: Int = min(max(ProcessInfo.processInfo.processorCount / 2, 4), 8),
        ramMB: Int = 4096,
        diskSizeMB: Int = 8192,
        gpuMode: GPUMode = .host,
        maxFPS: Int = 60,
        enableAudio: Bool = true,
        enableGamepad: Bool = true,
        enableQuickBoot: Bool = true,
        enableHardwareDecode: Bool = true,
        enableFlexDisplay: Bool = false,
        hideSystemDecorationsInAppMode: Bool = false,
        port: Int = 5554
    ) {
        self.avdName = avdName
        self.systemImage = systemImage
        self.cpuCores = cpuCores
        self.ramMB = ramMB
        self.diskSizeMB = diskSizeMB
        self.gpuMode = gpuMode
        self.maxFPS = maxFPS
        self.enableAudio = enableAudio
        self.enableGamepad = enableGamepad
        self.enableQuickBoot = enableQuickBoot
        self.enableHardwareDecode = enableHardwareDecode
        self.enableFlexDisplay = enableFlexDisplay
        self.hideSystemDecorationsInAppMode = hideSystemDecorationsInAppMode
        self.port = port
    }

    public init(from decoder: Decoder) throws {
        let defaults = EngineConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.avdName = try c.decodeIfPresent(String.self, forKey: .avdName) ?? defaults.avdName
        self.systemImage = try c.decodeIfPresent(SystemImageVariant.self, forKey: .systemImage) ?? defaults.systemImage
        self.cpuCores = try c.decodeIfPresent(Int.self, forKey: .cpuCores) ?? defaults.cpuCores
        self.ramMB = try c.decodeIfPresent(Int.self, forKey: .ramMB) ?? defaults.ramMB
        self.diskSizeMB = try c.decodeIfPresent(Int.self, forKey: .diskSizeMB) ?? defaults.diskSizeMB
        self.gpuMode = try c.decodeIfPresent(GPUMode.self, forKey: .gpuMode) ?? defaults.gpuMode
        self.maxFPS = try c.decodeIfPresent(Int.self, forKey: .maxFPS) ?? defaults.maxFPS
        self.enableAudio = try c.decodeIfPresent(Bool.self, forKey: .enableAudio) ?? defaults.enableAudio
        self.enableGamepad = try c.decodeIfPresent(Bool.self, forKey: .enableGamepad) ?? defaults.enableGamepad
        self.enableQuickBoot = try c.decodeIfPresent(Bool.self, forKey: .enableQuickBoot) ?? defaults.enableQuickBoot
        self.enableHardwareDecode = try c.decodeIfPresent(Bool.self, forKey: .enableHardwareDecode) ?? defaults.enableHardwareDecode
        self.enableFlexDisplay = try c.decodeIfPresent(Bool.self, forKey: .enableFlexDisplay) ?? defaults.enableFlexDisplay
        self.hideSystemDecorationsInAppMode = try c.decodeIfPresent(Bool.self, forKey: .hideSystemDecorationsInAppMode) ?? defaults.hideSystemDecorationsInAppMode
        self.port = try c.decodeIfPresent(Int.self, forKey: .port) ?? defaults.port
    }

    public var emulatorSerial: String {
        "emulator-\(port)"
    }

    public static func load(from url: URL) -> EngineConfig {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(EngineConfig.self, from: data) else {
            return EngineConfig()
        }
        return decoded
    }

    public func save(to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

public enum EngineState: Equatable, Sendable {
    case stopped
    case starting(String)
    case running(serial: String, androidVersion: String, gpuActive: String)
    case stopping
    case error(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var isBusy: Bool {
        switch self {
        case .starting, .stopping: return true
        default: return false
        }
    }

    public var statusLabel: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting(let phase): return phase
        case .running(_, let version, _): return "Running · Android \(version)"
        case .stopping: return "Stopping…"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

public struct AndroidAppInfo: Identifiable, Hashable, Codable, Sendable {
    public var id: String { packageName }
    public let packageName: String
    public let displayName: String
    public let isSystemApp: Bool
    public var iconPath: String?
    public var hasMacLauncher: Bool

    public init(
        packageName: String,
        displayName: String,
        isSystemApp: Bool,
        iconPath: String? = nil,
        hasMacLauncher: Bool = false
    ) {
        self.packageName = packageName
        self.displayName = displayName
        self.isSystemApp = isSystemApp
        self.iconPath = iconPath
        self.hasMacLauncher = hasMacLauncher
    }
}

public struct RuntimeStatus: Equatable, Sendable {
    public let javaPath: String?
    public let sdkManagerPath: String?
    public let avdManagerPath: String?
    public let adbPath: String?
    public let emulatorPath: String?
    public let scrcpyPath: String?
    public let systemImageInstalled: Bool
    public let avdExists: Bool
    public let architecture: String

    public init(
        javaPath: String?,
        sdkManagerPath: String?,
        avdManagerPath: String?,
        adbPath: String?,
        emulatorPath: String?,
        scrcpyPath: String?,
        systemImageInstalled: Bool,
        avdExists: Bool,
        architecture: String
    ) {
        self.javaPath = javaPath
        self.sdkManagerPath = sdkManagerPath
        self.avdManagerPath = avdManagerPath
        self.adbPath = adbPath
        self.emulatorPath = emulatorPath
        self.scrcpyPath = scrcpyPath
        self.systemImageInstalled = systemImageInstalled
        self.avdExists = avdExists
        self.architecture = architecture
    }

    public var isAppleSilicon: Bool {
        architecture == "arm64"
    }

    public var hasCoreTools: Bool {
        javaPath != nil && sdkManagerPath != nil && avdManagerPath != nil && adbPath != nil && scrcpyPath != nil
    }

    public var isReadyToBoot: Bool {
        adbPath != nil && emulatorPath != nil && scrcpyPath != nil && systemImageInstalled && avdExists
    }

    public var missingItems: [String] {
        var missing: [String] = []
        if javaPath == nil { missing.append("OpenJDK 21") }
        if sdkManagerPath == nil { missing.append("Android Command-line Tools (sdkmanager)") }
        if avdManagerPath == nil { missing.append("AVD Manager (avdmanager)") }
        if adbPath == nil { missing.append("Android Platform-Tools (adb)") }
        if scrcpyPath == nil { missing.append("scrcpy 5+") }
        if emulatorPath == nil { missing.append("Android Emulator Engine") }
        if !systemImageInstalled { missing.append("ARM64 Android 15 System Image") }
        if !avdExists { missing.append("DroidMac Virtual Device (AVD)") }
        return missing
    }
}

public struct ActiveWindowSession: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let packageName: String?
    public let title: String
    public let profile: LaunchProfile?
    public let pid: Int32
    public let startedAt: Date

    public init(
        id: UUID = UUID(),
        packageName: String?,
        title: String,
        profile: LaunchProfile?,
        pid: Int32,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.packageName = packageName
        self.title = title
        self.profile = profile
        self.pid = pid
        self.startedAt = startedAt
    }
}

public enum LogLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"
}

public struct LogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let source: String
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel = .info,
        source: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.source = source
        self.message = message
    }
}

public enum DroidMacError: LocalizedError, Sendable {
    case invalidPackageName(String)
    case invalidAVDName(String)
    case invalidAPKFile(String)
    case missingDependency(String)
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case emulatorBootTimeout
    case emulatorNotRunning
    case bundleCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPackageName(let pkg):
            return "Invalid Android package name: '\(pkg)'."
        case .invalidAVDName(let name):
            return "Invalid virtual device name: '\(name)'."
        case .invalidAPKFile(let reason):
            return "APK validation failed: \(reason)"
        case .missingDependency(let dep):
            return "Missing required component: \(dep). Run Setup to install it."
        case .commandFailed(let command, let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) exited with code \(exitCode)\(trimmed.isEmpty ? "" : ": \(trimmed)")"
        case .emulatorBootTimeout:
            return "Android engine did not finish booting within the timeout period."
        case .emulatorNotRunning:
            return "Android engine is not running. Start the engine first."
        case .bundleCreationFailed(let reason):
            return "Could not create macOS app launcher: \(reason)"
        }
    }
}

public enum Validator {
    public static func isValidPackageName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255, name.contains(".") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let segments = name.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy { !$0.isEmpty && !($0.first?.isNumber ?? false) }
    }

    public static func isValidAVDName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public static func sanitizeMacAppName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\*?\"<>|\0\n\r\t")
        let cleaned = name.components(separatedBy: forbidden).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Android App" : String(cleaned.prefix(64))
    }

    /// Verifies that a local file is a valid APK/XAPK/APKS zip archive before passing it to `adb install`.
    public static func validateAPKArchive(at url: URL) throws {
        let ext = url.pathExtension.lowercased()
        guard ["apk", "xapk", "apks", "apkm"].contains(ext) else {
            throw DroidMacError.invalidAPKFile("Unsupported file extension '.\(ext)'. Expected .apk, .xapk, or .apks.")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            throw DroidMacError.invalidAPKFile("File does not exist at \(url.path).")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 4) ?? Data()
        // ZIP magic bytes: PK\x03\x04
        guard header.count == 4,
              header[0] == 0x50, header[1] == 0x4B, header[2] == 0x03, header[3] == 0x04 else {
            throw DroidMacError.invalidAPKFile("File is not a valid ZIP/APK archive (invalid header signature).")
        }
    }
}
