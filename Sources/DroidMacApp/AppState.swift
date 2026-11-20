import Foundation
import AppKit
import Observation
import DroidMacCore

@MainActor
@Observable
public final class AppState {
    public let paths = DroidMacPaths()
    public let runtimeManager: RuntimeManager
    public let engine: EmulatorEngine
    public let adb: ADBClient
    public let windowLauncher: WindowLauncher
    public let bundleBuilder: MacAppBundleBuilder

    public var config: EngineConfig
    public var runtimeStatus: RuntimeStatus
    public var engineState: EngineState = .stopped
    public var installedApps: [AndroidAppInfo] = []
    public var activeWindows: [ActiveWindowSession] = []
    public var logs: [LogEntry] = []

    public var searchText: String = ""
    public var showSystemApps: Bool = false
    public var defaultProfile: LaunchProfile = .adaptiveApp
    public var isSettingUp: Bool = false
    public var isRefreshingApps: Bool = false
    public var isInstallingAPK: Bool = false
    public var bannerMessage: String?
    public var bannerIsError: Bool = false

    public init() {
        let paths = DroidMacPaths()
        let runner = ProcessRunner()
        let runtime = RuntimeManager(paths: paths, runner: runner)
        self.runtimeManager = runtime
        self.engine = EmulatorEngine(paths: paths, runner: runner, runtimeManager: runtime)
        self.adb = ADBClient(paths: paths, runner: runner)
        self.windowLauncher = WindowLauncher(paths: paths, runner: runner)
        self.bundleBuilder = MacAppBundleBuilder(paths: paths, runner: runner)

        let loadedConfig = EngineConfig.load(from: paths.configURL)
        self.config = loadedConfig
        self.runtimeStatus = runtime.inspectStatus(config: loadedConfig)
    }

    public var filteredApps: [AndroidAppInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return installedApps }
        return installedApps.filter {
            $0.displayName.lowercased().contains(query) || $0.packageName.lowercased().contains(query)
        }
    }

    public func saveConfig() {
        do {
            try config.save(to: paths.configURL)
        } catch {
            appendLog(LogEntry(level: .error, source: "Config", message: "Could not save settings: \(error.localizedDescription)"))
        }
    }

    public func appendLog(_ entry: LogEntry) {
        logs.append(entry)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    public func showNotice(_ message: String, isError: Bool = false) {
        bannerMessage = message
        bannerIsError = isError
    }

    public func clearBanner() {
        bannerMessage = nil
    }

    public func bootstrapOnLaunch() async {
        refreshRuntimeStatus()
        // Check if headless emulator is already running from a previous session or CLI launch
        let serial = config.emulatorSerial
        if await engine.isEmulatorOnline(serial: serial), await engine.isBootCompleted(serial: serial) {
            let version = await engine.queryAndroidVersion(serial: serial)
            let gpu = await engine.queryActiveGPURenderer(serial: serial)
            engineState = .running(serial: serial, androidVersion: version, gpuActive: gpu)
            appendLog(LogEntry(source: "Engine", message: "Connected to active Android \(version) VM (\(serial))."))
            await refreshApps()
        }
    }

    public func refreshRuntimeStatus() {
        runtimeStatus = runtimeManager.inspectStatus(config: config)
    }

    public func runSetup() async {
        guard !isSettingUp else { return }
        isSettingUp = true
        clearBanner()
        defer {
            isSettingUp = false
            refreshRuntimeStatus()
        }

        do {
            try await runtimeManager.setupRuntime(config: config) { [weak self] entry in
                Task { @MainActor in
                    self?.appendLog(entry)
                }
            }
            showNotice("Apple Silicon Android 15 runtime is ready.")
        } catch {
            showNotice(error.localizedDescription, isError: true)
            appendLog(LogEntry(level: .error, source: "Setup", message: error.localizedDescription))
        }
    }

    public func startEngine() async {
        guard !engineState.isBusy && !engineState.isRunning else { return }
        clearBanner()
        saveConfig()
        engineState = .starting("Initializing Apple Silicon VM…")

        do {
            let result = try await engine.start(
                config: config,
                onStatus: { [weak self] phase in
                    Task { @MainActor in
                        if case .starting = self?.engineState {
                            self?.engineState = .starting(phase)
                        }
                    }
                },
                onLog: { [weak self] entry in
                    Task { @MainActor in
                        self?.appendLog(entry)
                    }
                },
                onUnexpectedExit: { [weak self] code in
                    Task { @MainActor in
                        guard let self else { return }
                        if self.engineState.isRunning {
                            self.engineState = code == 0 ? .stopped : .error("VM exited unexpectedly (code \(code)).")
                            self.installedApps = []
                            await self.refreshActiveWindows()
                        }
                    }
                }
            )
            engineState = .running(
                serial: result.serial,
                androidVersion: result.androidVersion,
                gpuActive: result.gpuActive
            )
            await refreshApps()
        } catch {
            engineState = .error(error.localizedDescription)
            showNotice(error.localizedDescription, isError: true)
            appendLog(LogEntry(level: .error, source: "Engine", message: error.localizedDescription))
        }
    }

    public func stopEngine() async {
        guard !engineState.isBusy else { return }
        clearBanner()
        engineState = .stopping
        await windowLauncher.closeAllWindows()
        activeWindows = []
        await engine.stop(serial: config.emulatorSerial) { [weak self] entry in
            Task { @MainActor in
                self?.appendLog(entry)
            }
        }
        installedApps = []
        engineState = .stopped
    }

    public func refreshApps() async {
        guard case .running(let serial, _, _) = engineState else { return }
        guard !isRefreshingApps else { return }
        isRefreshingApps = true
        defer { isRefreshingApps = false }

        do {
            let list = try await adb.listLaunchableApps(serial: serial, includeSystem: showSystemApps)
            installedApps = list
            // Extract icons lazily in the background for apps missing cached icons
            let packagesNeedingIcons = list.filter { $0.iconPath == nil }.prefix(16).map(\.packageName)
            if !packagesNeedingIcons.isEmpty {
                Task.detached(priority: .utility) { [adb] in
                    for pkg in packagesNeedingIcons {
                        if let url = await adb.extractAppIcon(serial: serial, packageName: pkg) {
                            await MainActor.run { [weak self] in
                                guard let self,
                                      let idx = self.installedApps.firstIndex(where: { $0.packageName == pkg }) else { return }
                                self.installedApps[idx].iconPath = url.path
                            }
                        }
                    }
                }
            }
        } catch {
            appendLog(LogEntry(level: .error, source: "Apps", message: error.localizedDescription))
        }
    }

    public func launchApp(_ app: AndroidAppInfo, profile: LaunchProfile? = nil) async {
        let chosenProfile = profile ?? defaultProfile
        clearBanner()
        if !engineState.isRunning {
            await startEngine()
        }
        guard case .running(let serial, _, _) = engineState else { return }

        do {
            let session = try await windowLauncher.launchAppWindow(
                serial: serial,
                packageName: app.packageName,
                windowTitle: app.displayName,
                profile: chosenProfile,
                config: config,
                onLog: { [weak self] entry in
                    Task { @MainActor in self?.appendLog(entry) }
                },
                onWindowClosed: { [weak self] _ in
                    Task { @MainActor in await self?.refreshActiveWindows() }
                }
            )
            activeWindows.append(session)
        } catch {
            showNotice(error.localizedDescription, isError: true)
            appendLog(LogEntry(level: .error, source: "Window", message: error.localizedDescription))
        }
    }

    public func launchFullDeviceScreen() async {
        clearBanner()
        if !engineState.isRunning {
            await startEngine()
        }
        guard case .running(let serial, let version, _) = engineState else { return }

        do {
            let session = try await windowLauncher.launchFullDeviceWindow(
                serial: serial,
                windowTitle: "DroidMac · Android \(version)",
                config: config,
                onLog: { [weak self] entry in
                    Task { @MainActor in self?.appendLog(entry) }
                },
                onWindowClosed: { [weak self] _ in
                    Task { @MainActor in await self?.refreshActiveWindows() }
                }
            )
            activeWindows.append(session)
        } catch {
            showNotice(error.localizedDescription, isError: true)
        }
    }

    public func launchPlayStore() async {
        let playStore = AndroidAppInfo(
            packageName: "com.android.vending",
            displayName: "Google Play Store",
            isSystemApp: true
        )
        await launchApp(playStore, profile: .adaptiveApp)
    }

    public func closeWindow(_ id: UUID) async {
        await windowLauncher.closeWindow(id: id)
        await refreshActiveWindows()
    }

    public func refreshActiveWindows() async {
        activeWindows = await windowLauncher.listActiveSessions()
    }

    public func installAPK(from url: URL) async {
        clearBanner()
        if !engineState.isRunning {
            await startEngine()
        }
        guard case .running(let serial, _, _) = engineState else { return }

        isInstallingAPK = true
        defer { isInstallingAPK = false }

        do {
            try await adb.installPackage(serial: serial, fileURL: url) { [weak self] entry in
                Task { @MainActor in self?.appendLog(entry) }
            }
            showNotice("Installed \(url.lastPathComponent).")
            await refreshApps()
        } catch {
            showNotice(error.localizedDescription, isError: true)
            appendLog(LogEntry(level: .error, source: "Installer", message: error.localizedDescription))
        }
    }

    public func uninstallApp(_ app: AndroidAppInfo) async {
        guard case .running(let serial, _, _) = engineState else { return }
        clearBanner()
        do {
            try await adb.uninstallPackage(serial: serial, packageName: app.packageName)
            try? bundleBuilder.removeMacAppBundle(for: app.displayName)
            showNotice("Uninstalled \(app.displayName).")
            await refreshApps()
        } catch {
            showNotice(error.localizedDescription, isError: true)
        }
    }

    public func createMacLauncher(for app: AndroidAppInfo, profile: LaunchProfile? = nil) async {
        clearBanner()
        let chosenProfile = profile ?? defaultProfile
        var iconURL: URL? = app.iconPath.map { URL(fileURLWithPath: $0) }
        if iconURL == nil, case .running(let serial, _, _) = engineState {
            iconURL = await adb.extractAppIcon(serial: serial, packageName: app.packageName)
        }

        do {
            let bundleURL = try await bundleBuilder.createMacAppBundle(
                for: app,
                profile: chosenProfile,
                iconPNGURL: iconURL
            )
            if let idx = installedApps.firstIndex(where: { $0.packageName == app.packageName }) {
                installedApps[idx].hasMacLauncher = true
                if let iconURL {
                    installedApps[idx].iconPath = iconURL.path
                }
            }
            showNotice("Created macOS app: \(bundleURL.lastPathComponent) in ~/Applications/DroidMac Apps/")
            appendLog(LogEntry(source: "Launcher", message: "Created \(bundleURL.path)"))
        } catch {
            showNotice(error.localizedDescription, isError: true)
            appendLog(LogEntry(level: .error, source: "Launcher", message: error.localizedDescription))
        }
    }

    public func removeMacLauncher(for app: AndroidAppInfo) {
        do {
            try bundleBuilder.removeMacAppBundle(for: app.displayName)
            if let idx = installedApps.firstIndex(where: { $0.packageName == app.packageName }) {
                installedApps[idx].hasMacLauncher = false
            }
            showNotice("Removed macOS launcher for \(app.displayName).")
        } catch {
            showNotice(error.localizedDescription, isError: true)
        }
    }

    public func pushFileToAndroid(from url: URL) async {
        guard case .running(let serial, _, _) = engineState else {
            showNotice("Start the Android engine before transferring files.", isError: true)
            return
        }
        do {
            try await adb.pushFileToDownloads(serial: serial, fileURL: url)
            showNotice("Sent \(url.lastPathComponent) to Android Downloads folder.")
        } catch {
            showNotice(error.localizedDescription, isError: true)
        }
    }

    public func openLaunchersFolderInFinder() {
        try? paths.ensureDirectoriesExist()
        NSWorkspace.shared.open(paths.launchersDir)
    }

    public func openSDKFolderInFinder() {
        try? paths.ensureDirectoriesExist()
        NSWorkspace.shared.open(paths.appSupportDir)
    }

    public func shutdownSynchronouslyForQuit() {
        saveConfig()
        let sem = DispatchSemaphore(value: 0)
        let serial = config.emulatorSerial
        let launcher = self.windowLauncher
        let eng = self.engine
        Task.detached {
            await launcher.closeAllWindows()
            await eng.stop(serial: serial)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 9)
    }
}
