import SwiftUI
import UniformTypeIdentifiers
import AppKit
import DroidMacCore

struct LibraryView: View {
    @Bindable var state: AppState
    @State private var isDropTargeted = false

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !state.engineState.isRunning {
                stoppedEmptyState
            } else {
                topControlsBar
                Divider()
                if state.isRefreshingApps && state.installedApps.isEmpty {
                    ProgressView("Loading installed Android apps…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if state.filteredApps.isEmpty {
                    emptySearchState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(state.filteredApps) { app in
                                AppRowTile(app: app, state: state)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.accentColor)
                            Text("Drop APK, XAPK, or APKS to Install")
                                .font(.headline)
                        }
                    }
                    .padding(12)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private var topControlsBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter apps or package names…", text: $state.searchText)
                    .textFieldStyle(.plain)
                if !state.searchText.isEmpty {
                    Button {
                        state.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .frame(maxWidth: 300)

            Picker("Launch As", selection: $state.defaultProfile) {
                ForEach(LaunchProfile.allCases) { profile in
                    Label(profile.displayName, systemImage: profile.sfSymbol)
                        .tag(profile)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)

            Toggle("System Apps", isOn: $state.showSystemApps)
                .toggleStyle(.checkbox)
                .onChange(of: state.showSystemApps) { _, _ in
                    Task { await state.refreshApps() }
                }

            Spacer()

            Button {
                pickAndInstallAPK()
            } label: {
                Label(state.isInstallingAPK ? "Installing…" : "Install APK", systemImage: "plus.app")
            }
            .disabled(state.isInstallingAPK)

            Button {
                Task { await state.launchPlayStore() }
            } label: {
                Label("Play Store", systemImage: "bag")
            }

            Button {
                Task { await state.refreshApps() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh installed apps")
            .disabled(state.isRefreshingApps)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var stoppedEmptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Android Engine Is Stopped")
                    .font(.title2.weight(.semibold))
                Text("Start the headless ARM64 Android engine to browse your apps, install APKs, and open Android apps or games in standalone native macOS windows.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await state.startEngine() }
                } label: {
                    HStack(spacing: 8) {
                        if state.engineState.isBusy {
                            ProgressView().controlSize(.small)
                        }
                        Text(state.engineState.isBusy ? state.engineState.statusLabel : "Start Android Engine")
                    }
                    .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(state.engineState.isBusy)

                Button("Open Mac Launchers Folder") {
                    state.openLaunchersFolderInFinder()
                }
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var emptySearchState: some View {
        VStack(spacing: 10) {
            Text(state.searchText.isEmpty ? "No Apps Found" : "No Matching Apps")
                .font(.headline)
            Text(state.searchText.isEmpty
                 ? "Install an APK via drag-and-drop or open Google Play Store to download apps and games."
                 : "Try another search term or enable System Apps.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Install APK…") { pickAndInstallAPK() }
                Button("Open Play Store") { Task { await state.launchPlayStore() } }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickAndInstallAPK() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Android Package"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "apk") ?? .data,
            UTType(filenameExtension: "xapk") ?? .data,
            UTType(filenameExtension: "apks") ?? .data,
            UTType(filenameExtension: "apkm") ?? .data
        ]
        if panel.runModal() == .OK, let url = panel.url {
            Task { await state.installAPK(from: url) }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let ext = url.pathExtension.lowercased()
            Task { @MainActor in
                if ["apk", "xapk", "apks", "apkm"].contains(ext) {
                    await state.installAPK(from: url)
                } else {
                    await state.pushFileToAndroid(from: url)
                }
            }
        }
        return true
    }
}

private struct AppRowTile: View {
    let app: AndroidAppInfo
    @Bindable var state: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            appIconView
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if app.hasMacLauncher {
                        Image(systemName: "app.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Installed as native macOS launcher in ~/Applications/DroidMac Apps/")
                    }
                }
                Text(app.packageName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Button("Open") {
                    Task { await state.launchApp(app) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Menu {
                    ForEach(LaunchProfile.allCases) { profile in
                        Button {
                            Task { await state.launchApp(app, profile: profile) }
                        } label: {
                            Label("Open as \(profile.displayName)", systemImage: profile.sfSymbol)
                        }
                    }

                    Divider()

                    if app.hasMacLauncher {
                        Button("Update Mac App (.app)") {
                            Task { await state.createMacLauncher(for: app) }
                        }
                        Button("Remove Mac App (.app)", role: .destructive) {
                            state.removeMacLauncher(for: app)
                        }
                    } else {
                        Button {
                            Task { await state.createMacLauncher(for: app) }
                        } label: {
                            Label("Add to Mac Applications (.app)", systemImage: "square.and.arrow.down")
                        }
                    }

                    if !app.isSystemApp {
                        Divider()
                        Button("Uninstall from Android", role: .destructive) {
                            Task { await state.uninstallApp(app) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(12)
        .background(
            Color(nsColor: isHovered ? .selectedControlColor.withAlphaComponent(0.14) : .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var appIconView: some View {
        if let path = app.iconPath, let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.15))
                .overlay {
                    Text(String(app.displayName.prefix(1)).uppercased())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
        }
    }
}
