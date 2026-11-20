import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public final class MacAppBundleBuilder: Sendable {
    public let paths: DroidMacPaths
    public let runner: ProcessRunner

    public init(paths: DroidMacPaths = DroidMacPaths(), runner: ProcessRunner = ProcessRunner()) {
        self.paths = paths
        self.runner = runner
    }

    public func createMacAppBundle(
        for app: AndroidAppInfo,
        profile: LaunchProfile,
        iconPNGURL: URL? = nil,
        cliBinaryPath: String? = nil
    ) async throws -> URL {
        guard Validator.isValidPackageName(app.packageName) else {
            throw DroidMacError.invalidPackageName(app.packageName)
        }
        try paths.ensureDirectoriesExist()

        let safeName = Validator.sanitizeMacAppName(app.displayName)
        let bundleURL = paths.macAppBundleURL(for: safeName)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        let fm = FileManager.default
        if fm.fileExists(atPath: bundleURL.path) {
            try fm.removeItem(at: bundleURL)
        }
        try fm.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        // 1. Build .icns icon
        let sourcePNG: URL
        var tempFallbackPNG: URL?
        if let iconPNGURL, fm.fileExists(atPath: iconPNGURL.path) {
            sourcePNG = iconPNGURL
        } else {
            let fallback = fm.temporaryDirectory.appendingPathComponent("DroidMacFallback-\(UUID().uuidString).png")
            try Self.renderFallbackIconPNG(label: safeName, to: fallback)
            sourcePNG = fallback
            tempFallbackPNG = fallback
        }
        defer {
            if let tempFallbackPNG { try? fm.removeItem(at: tempFallbackPNG) }
        }

        let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")
        let builtIcon = await buildICNS(fromPNG: sourcePNG, toICNS: icnsURL)

        // 2. Write Info.plist
        let bundleID = "com.droidmac.launcher.\(app.packageName)"
        let infoPlist: [String: Any] = [
            "CFBundleName": safeName,
            "CFBundleDisplayName": safeName,
            "CFBundleIdentifier": bundleID,
            "CFBundleVersion": "1.0",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "DroidMacLauncher",
            "CFBundleIconFile": builtIcon ? "AppIcon" : "",
            "LSMinimumSystemVersion": "15.0",
            "NSHighResolutionCapable": true,
            "LSUIElement": true,
            "DroidMacPackageName": app.packageName,
            "DroidMacLaunchProfile": profile.rawValue
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"), options: .atomic)

        // 3. Write safe launcher executable
        let cliPath = cliBinaryPath
            ?? paths.resolveCLIPath()
            ?? paths.cliBinaryDir.appendingPathComponent("DroidMacCLI").path

        let script = Self.buildLauncherScript(
            cliPath: cliPath,
            packageName: app.packageName,
            profile: profile,
            title: safeName
        )
        let executableURL = macOSURL.appendingPathComponent("DroidMacLauncher")
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        return bundleURL
    }

    public func removeMacAppBundle(for displayName: String) throws {
        let bundleURL = paths.macAppBundleURL(for: displayName)
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            try FileManager.default.removeItem(at: bundleURL)
        }
    }

    public static func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func buildLauncherScript(
        cliPath: String,
        packageName: String,
        profile: LaunchProfile,
        title: String
    ) -> String {
        """
        #!/bin/sh
        set -eu
        CLI=\(shellSingleQuote(cliPath))
        if [ ! -x "$CLI" ]; then
            osascript -e 'display alert "DroidMac CLI Missing" message "Please open DroidMac.app once to install the helper binary."'
            exit 1
        fi
        exec "$CLI" launch --package \(shellSingleQuote(packageName)) --profile \(shellSingleQuote(profile.rawValue)) --title \(shellSingleQuote(title))
        """
    }

    private func buildICNS(fromPNG sourcePNG: URL, toICNS destICNS: URL) async -> Bool {
        let fm = FileManager.default
        let iconsetDir = fm.temporaryDirectory
            .appendingPathComponent("DroidMac-\(UUID().uuidString).iconset", isDirectory: true)
        do {
            try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
        } catch {
            return false
        }
        defer { try? fm.removeItem(at: iconsetDir) }

        let sizes: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512)
        ]

        for (filename, px) in sizes {
            let outPath = iconsetDir.appendingPathComponent(filename).path
            guard let res = try? await runner.run(
                executablePath: "/usr/bin/sips",
                arguments: ["-z", "\(px)", "\(px)", sourcePNG.path, "--out", outPath],
                timeoutSeconds: 10
            ), res.succeeded else {
                return false
            }
        }

        guard let iconutil = try? await runner.run(
            executablePath: "/usr/bin/iconutil",
            arguments: ["-c", "icns", iconsetDir.path, "-o", destICNS.path],
            timeoutSeconds: 15
        ), iconutil.succeeded else {
            return false
        }
        return fm.fileExists(atPath: destICNS.path)
    }

    public static func renderFallbackIconPNG(label: String, to destinationURL: URL) throws {
        let size = 512
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DroidMacError.bundleCreationFailed("Failed to allocate graphics context for icon.")
        }

        // Deterministic pleasant tint from label hash
        let hash = abs(label.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.14, 0.52, 0.41), // emerald
            (0.16, 0.42, 0.68), // cobalt
            (0.68, 0.34, 0.18), // terracotta
            (0.36, 0.33, 0.66), // slate indigo
            (0.18, 0.50, 0.56)  // deep teal
        ]
        let (r, g, b) = palette[hash % palette.count]

        let inset: CGFloat = 44
        let rect = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
        let cornerRadius: CGFloat = 96
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        ctx.addPath(path)
        ctx.clip()

        let topColor = CGColor(red: min(r + 0.12, 1), green: min(g + 0.12, 1), blue: min(b + 0.12, 1), alpha: 1)
        let bottomColor = CGColor(red: max(r - 0.08, 0), green: max(g - 0.08, 0), blue: max(b - 0.08, 0), alpha: 1)
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: [topColor, bottomColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) - inset),
                end: CGPoint(x: CGFloat(size) / 2, y: inset),
                options: []
            )
        }

        // Minimal geometric inner frame badge
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
        ctx.setLineWidth(8)
        let innerRect = rect.insetBy(dx: 70, dy: 70)
        let innerPath = CGPath(roundedRect: innerRect, cornerWidth: 42, cornerHeight: 42, transform: nil)
        ctx.addPath(innerPath)
        ctx.strokePath()

        // Simple Android-inspired twin antenna + dome silhouette in crisp white
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
        let domeRect = CGRect(x: 166, y: 170, width: 180, height: 150)
        let domePath = CGPath(roundedRect: domeRect, cornerWidth: 74, cornerHeight: 74, transform: nil)
        ctx.addPath(domePath)
        ctx.fillPath()

        // Eyes
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 210, y: 235, width: 22, height: 22))
        ctx.fillEllipse(in: CGRect(x: 280, y: 235, width: 22, height: 22))

        guard let image = ctx.makeImage(),
              let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw DroidMacError.bundleCreationFailed("Failed to encode icon PNG.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DroidMacError.bundleCreationFailed("Failed to write icon PNG.")
        }
    }
}
