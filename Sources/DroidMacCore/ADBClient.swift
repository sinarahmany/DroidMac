import Foundation

public final class ADBClient: Sendable {
    public let paths: DroidMacPaths
    public let runner: ProcessRunner

    public init(paths: DroidMacPaths = DroidMacPaths(), runner: ProcessRunner = ProcessRunner()) {
        self.paths = paths
        self.runner = runner
    }

    private func requireADB() throws -> String {
        guard let adb = paths.resolveExecutable("adb") else {
            throw DroidMacError.missingDependency("adb")
        }
        return adb
    }

    /// Lists launchable apps with real localized display names using `scrcpy --list-apps`, falling back to `pm list packages`.
    public func listLaunchableApps(serial: String, includeSystem: Bool) async throws -> [AndroidAppInfo] {
        let env = paths.buildEnvironment()

        // Preferred path: scrcpy --list-apps gives real localized Android app names + system/user tags
        if let scrcpy = paths.resolveExecutable("scrcpy") {
            let result = try await runner.run(
                executablePath: scrcpy,
                arguments: ["-s", serial, "--list-apps"],
                environment: env,
                timeoutSeconds: 25
            )
            if result.succeeded {
                let parsed = Self.parseScrcpyAppList(
                    result.stdout,
                    includeSystem: includeSystem,
                    paths: paths
                )
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }

        // Fallback path: adb pm list packages
        let adb = try requireADB()
        var args = ["-s", serial, "shell", "pm", "list", "packages"]
        if !includeSystem {
            args.append("-3")
        }
        let result = try await runner.run(
            executablePath: adb,
            arguments: args,
            environment: env,
            timeoutSeconds: 20
        )
        guard result.succeeded else {
            throw DroidMacError.commandFailed(command: "adb pm list packages", exitCode: result.exitCode, stderr: result.stderr)
        }

        let fm = FileManager.default
        var apps: [AndroidAppInfo] = []
        for rawLine in result.stdout.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("package:") else { continue }
            let pkg = String(line.dropFirst("package:".count))
            guard Validator.isValidPackageName(pkg) else { continue }
            let label = Self.fallbackDisplayName(for: pkg)
            let iconURL = paths.iconCacheDir.appendingPathComponent("\(pkg).png")
            let launcherURL = paths.macAppBundleURL(for: label)
            apps.append(AndroidAppInfo(
                packageName: pkg,
                displayName: label,
                isSystemApp: includeSystem,
                iconPath: fm.fileExists(atPath: iconURL.path) ? iconURL.path : nil,
                hasMacLauncher: fm.fileExists(atPath: launcherURL.path)
            ))
        }
        return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Parses output of `scrcpy --list-apps`:
    /// ` * Google Play Store                com.android.vending`
    /// ` - Some Game                        com.example.game`
    public static func parseScrcpyAppList(
        _ output: String,
        includeSystem: Bool,
        paths: DroidMacPaths
    ) -> [AndroidAppInfo] {
        let fm = FileManager.default
        let curatedSystemApps: Set<String> = [
            "com.android.vending",
            "com.android.settings",
            "com.android.chrome",
            "com.google.android.youtube",
            "com.google.android.apps.photos",
            "com.google.android.calculator",
            "com.google.android.deskclock",
            "com.google.android.apps.docs",
            "com.google.android.gm",
            "com.google.android.apps.maps",
            "com.google.android.documentsui",
            "com.android.documentsui"
        ]

        var results: [AndroidAppInfo] = []
        var seen = Set<String>()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let isSystem: Bool
            let body: String
            if trimmed.hasPrefix("* ") {
                isSystem = true
                body = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- ") {
                isSystem = false
                body = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else {
                continue
            }

            // Package name is always the trailing whitespace-separated token
            guard let lastSpace = body.lastIndex(where: \.isWhitespace) else { continue }
            let pkg = String(body[body.index(after: lastSpace)...]).trimmingCharacters(in: .whitespaces)
            let name = String(body[..<lastSpace]).trimmingCharacters(in: .whitespaces)
            guard Validator.isValidPackageName(pkg), !name.isEmpty, !seen.contains(pkg) else { continue }
            seen.insert(pkg)

            if isSystem && !includeSystem && !curatedSystemApps.contains(pkg) {
                continue
            }

            let iconURL = paths.iconCacheDir.appendingPathComponent("\(pkg).png")
            let launcherURL = paths.macAppBundleURL(for: name)
            results.append(AndroidAppInfo(
                packageName: pkg,
                displayName: name,
                isSystemApp: isSystem,
                iconPath: fm.fileExists(atPath: iconURL.path) ? iconURL.path : nil,
                hasMacLauncher: fm.fileExists(atPath: launcherURL.path)
            ))
        }

        return results.sorted { lhs, rhs in
            if lhs.isSystemApp != rhs.isSystemApp {
                return !lhs.isSystemApp // User apps & games first
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    public static func fallbackDisplayName(for packageName: String) -> String {
        let last = packageName.split(separator: ".").last.map(String.init) ?? packageName
        return last
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Installs a validated `.apk`, `.xapk`, `.apks`, or `.apkm` package onto the Android VM.
    public func installPackage(
        serial: String,
        fileURL: URL,
        onLog: (@Sendable (LogEntry) -> Void)? = nil
    ) async throws {
        try Validator.validateAPKArchive(at: fileURL)
        let adb = try requireADB()
        let env = paths.buildEnvironment()
        let ext = fileURL.pathExtension.lowercased()

        if ext == "apk" {
            onLog?(LogEntry(source: "Installer", message: "Installing \(fileURL.lastPathComponent)…"))
            let result = try await runner.run(
                executablePath: adb,
                arguments: ["-s", serial, "install", "-r", "-g", fileURL.path],
                environment: env,
                timeoutSeconds: 180
            )
            guard result.succeeded else {
                throw DroidMacError.commandFailed(command: "adb install", exitCode: result.exitCode, stderr: result.stderr + "\n" + result.stdout)
            }
            onLog?(LogEntry(source: "Installer", message: "Installed \(fileURL.lastPathComponent) successfully."))
            return
        }

        // Split APK archive (.xapk / .apks / .apkm)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DroidMacInstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        onLog?(LogEntry(source: "Installer", message: "Extracting split archive \(fileURL.lastPathComponent)…"))
        let unzip = try await runner.run(
            executablePath: "/usr/bin/unzip",
            arguments: ["-oq", fileURL.path, "-d", tempDir.path],
            timeoutSeconds: 60
        )
        guard unzip.succeeded else {
            throw DroidMacError.invalidAPKFile("Could not unpack split archive: \(unzip.stderr)")
        }

        let apkPaths = Self.findAPKFiles(in: tempDir)
        guard !apkPaths.isEmpty else {
            throw DroidMacError.invalidAPKFile("No .apk payloads found inside \(fileURL.lastPathComponent).")
        }

        onLog?(LogEntry(source: "Installer", message: "Installing \(apkPaths.count) split APK files…"))
        let result = try await runner.run(
            executablePath: adb,
            arguments: ["-s", serial, "install-multiple", "-r", "-g"] + apkPaths,
            environment: env,
            timeoutSeconds: 240
        )
        guard result.succeeded else {
            throw DroidMacError.commandFailed(command: "adb install-multiple", exitCode: result.exitCode, stderr: result.stderr + "\n" + result.stdout)
        }
        onLog?(LogEntry(source: "Installer", message: "Installed split package \(fileURL.lastPathComponent) successfully."))
    }

    public func uninstallPackage(serial: String, packageName: String) async throws {
        guard Validator.isValidPackageName(packageName) else {
            throw DroidMacError.invalidPackageName(packageName)
        }
        let adb = try requireADB()
        let result = try await runner.run(
            executablePath: adb,
            arguments: ["-s", serial, "uninstall", packageName],
            environment: paths.buildEnvironment(),
            timeoutSeconds: 60
        )
        guard result.succeeded else {
            throw DroidMacError.commandFailed(command: "adb uninstall", exitCode: result.exitCode, stderr: result.stderr + "\n" + result.stdout)
        }
    }

    public func pushFileToDownloads(serial: String, fileURL: URL) async throws {
        let adb = try requireADB()
        let safeName = fileURL.lastPathComponent
        let dest = "/sdcard/Download/\(safeName)"
        let result = try await runner.run(
            executablePath: adb,
            arguments: ["-s", serial, "push", fileURL.path, dest],
            environment: paths.buildEnvironment(),
            timeoutSeconds: 120
        )
        guard result.succeeded else {
            throw DroidMacError.commandFailed(command: "adb push", exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Extracts the best available launcher icon PNG from the installed app's APK on the emulator and caches it locally.
    public func extractAppIcon(serial: String, packageName: String) async -> URL? {
        guard Validator.isValidPackageName(packageName) else { return nil }
        let cachedURL = paths.iconCacheDir.appendingPathComponent("\(packageName).png")
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }
        guard let adb = try? requireADB() else { return nil }
        let env = paths.buildEnvironment()

        guard let pathResult = try? await runner.run(
            executablePath: adb,
            arguments: ["-s", serial, "shell", "pm", "path", packageName],
            environment: env,
            timeoutSeconds: 15
        ), pathResult.succeeded else { return nil }

        let apkRemotePath = pathResult.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix("package:") && $0.hasSuffix(".apk") })
            .map { String($0.dropFirst("package:".count)) }

        guard let remotePath = apkRemotePath else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DroidMacIcon-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let localAPK = tempDir.appendingPathComponent("base.apk")
        guard let pullRes = try? await runner.run(
            executablePath: adb,
            arguments: ["-s", serial, "pull", remotePath, localAPK.path],
            environment: env,
            timeoutSeconds: 30
        ), pullRes.succeeded else { return nil }

        guard let listRes = try? await runner.run(
            executablePath: "/usr/bin/unzip",
            arguments: ["-Z1", localAPK.path],
            timeoutSeconds: 15
        ), listRes.succeeded else { return nil }

        let entries = listRes.stdout.split(whereSeparator: \.isNewline).map(String.init)
        guard let bestIconEntry = Self.pickBestIconEntry(from: entries) else { return nil }

        guard let extractRes = try? await runner.run(
            executablePath: "/usr/bin/unzip",
            arguments: ["-oj", localAPK.path, bestIconEntry, "-d", tempDir.path],
            timeoutSeconds: 15
        ), extractRes.succeeded else { return nil }

        let extractedFile = tempDir.appendingPathComponent(URL(fileURLWithPath: bestIconEntry).lastPathComponent)
        guard FileManager.default.fileExists(atPath: extractedFile.path) else { return nil }

        try? FileManager.default.createDirectory(at: paths.iconCacheDir, withIntermediateDirectories: true)
        let sipsRes = try? await runner.run(
            executablePath: "/usr/bin/sips",
            arguments: ["-s", "format", "png", "-Z", "256", extractedFile.path, "--out", cachedURL.path],
            timeoutSeconds: 15
        )
        if sipsRes?.succeeded == true, FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }
        return nil
    }

    public static func pickBestIconEntry(from entries: [String]) -> String? {
        let imageEntries = entries.filter { entry in
            let lower = entry.lowercased()
            let isImage = lower.hasSuffix(".png") || lower.hasSuffix(".webp")
            guard isImage else { return false }
            return lower.contains("ic_launcher") && !lower.contains("background") && !lower.contains("monochrome")
        }
        guard !imageEntries.isEmpty else { return nil }

        func score(_ entry: String) -> Int {
            let lower = entry.lowercased()
            var s = 0
            if lower.contains("xxxhdpi") { s += 50 }
            else if lower.contains("xxhdpi") { s += 40 }
            else if lower.contains("xhdpi") { s += 30 }
            else if lower.contains("hdpi") { s += 20 }
            if lower.hasSuffix(".png") { s += 15 } // sips handles PNG natively even on older builds
            if lower.contains("round") { s += 5 }
            if lower.contains("foreground") { s -= 10 }
            return s
        }

        return imageEntries.max(by: { score($0) < score($1) })
    }

    private static func findAPKFiles(in directory: URL) -> [String] {
        var apkPaths: [String] = []
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let item as URL in enumerator where item.pathExtension.lowercased() == "apk" {
                apkPaths.append(item.path)
            }
        }
        return apkPaths.sorted()
    }
}
