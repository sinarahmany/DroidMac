import Foundation

public struct DroidMacPaths: Sendable {
    public let appSupportDir: URL
    public let sdkRoot: URL
    public let avdHome: URL
    public let iconCacheDir: URL
    public let configURL: URL
    public let launchersDir: URL
    public let cliBinaryDir: URL

    public init(
        appSupportDir: URL? = nil,
        launchersDir: URL? = nil
    ) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let support = appSupportDir ?? home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("DroidMac", isDirectory: true)

        self.appSupportDir = support
        self.sdkRoot = support.appendingPathComponent("android-sdk", isDirectory: true)
        self.avdHome = support.appendingPathComponent("avd", isDirectory: true)
        self.iconCacheDir = support.appendingPathComponent("icons", isDirectory: true)
        self.configURL = support.appendingPathComponent("config.json")
        self.cliBinaryDir = support.appendingPathComponent("bin", isDirectory: true)
        self.launchersDir = launchersDir ?? home
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("DroidMac Apps", isDirectory: true)
    }

    public func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        for dir in [appSupportDir, sdkRoot, avdHome, iconCacheDir, cliBinaryDir, launchersDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func resolveJavaHome() -> String? {
        let candidates = [
            "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
            "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home",
            "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home",
            "/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
            "/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home",
            "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home",
            "/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home",
            "/Library/Java/JavaVirtualMachines/openjdk-21.jdk/Contents/Home"
        ]
        let fm = FileManager.default
        for path in candidates {
            let javaBin = URL(fileURLWithPath: path).appendingPathComponent("bin/java").path
            if fm.isExecutableFile(atPath: javaBin) {
                return path
            }
        }
        return nil
    }

    public func resolveExecutable(_ name: String, extraSearchPaths: [String] = []) -> String? {
        let fm = FileManager.default
        var searchDirs: [String] = extraSearchPaths
        searchDirs.append(contentsOf: [
            sdkRoot.appendingPathComponent("emulator").path,
            sdkRoot.appendingPathComponent("platform-tools").path,
            sdkRoot.appendingPathComponent("cmdline-tools/latest/bin").path,
            "/opt/homebrew/bin",
            "/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin",
            "/usr/local/bin",
            "/usr/local/share/android-commandlinetools/cmdline-tools/latest/bin",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk/emulator").path,
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk/platform-tools").path,
            cliBinaryDir.path,
            "/usr/bin",
            "/bin"
        ])

        for dir in searchDirs {
            let full = URL(fileURLWithPath: dir).appendingPathComponent(name).path
            if fm.isExecutableFile(atPath: full) {
                return full
            }
        }
        return nil
    }

    public func resolveCLIPath() -> String? {
        let fm = FileManager.default
        let installed = cliBinaryDir.appendingPathComponent("DroidMacCLI").path
        if fm.isExecutableFile(atPath: installed) {
            return installed
        }
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let bundled = execDir.appendingPathComponent("DroidMacCLI").path
            if fm.isExecutableFile(atPath: bundled) {
                return bundled
            }
        }
        return nil
    }

    public func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ANDROID_SDK_ROOT"] = sdkRoot.path
        env["ANDROID_HOME"] = sdkRoot.path
        env["ANDROID_AVD_HOME"] = avdHome.path

        if let javaHome = resolveJavaHome() {
            env["JAVA_HOME"] = javaHome
        }

        var pathEntries: [String] = []
        if let javaHome = env["JAVA_HOME"] {
            pathEntries.append("\(javaHome)/bin")
        }
        pathEntries.append(contentsOf: [
            sdkRoot.appendingPathComponent("emulator").path,
            sdkRoot.appendingPathComponent("platform-tools").path,
            sdkRoot.appendingPathComponent("cmdline-tools/latest/bin").path,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])
        env["PATH"] = pathEntries.joined(separator: ":")
        return env
    }

    public func avdDirectory(named avdName: String) -> URL {
        avdHome.appendingPathComponent("\(avdName).avd", isDirectory: true)
    }

    public func avdConfigINI(named avdName: String) -> URL {
        avdDirectory(named: avdName).appendingPathComponent("config.ini")
    }

    public func systemImageDirectory(for variant: SystemImageVariant) -> URL {
        // "system-images;android-35;google_apis_playstore;arm64-v8a"
        let parts = variant.rawValue.split(separator: ";").map(String.init)
        return parts.reduce(sdkRoot) { partial, part in
            partial.appendingPathComponent(part, isDirectory: true)
        }
    }

    public func macAppBundleURL(for displayName: String) -> URL {
        let safe = Validator.sanitizeMacAppName(displayName)
        return launchersDir.appendingPathComponent("\(safe).app", isDirectory: true)
    }

    public static var hostArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
