import SwiftUI
import DroidMacCore

enum SidebarTab: String, CaseIterable, Identifiable {
    case library = "Apps & Games"
    case windows = "Active Windows"
    case settings = "Performance & Safety"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .library: return "square.grid.2x2"
        case .windows: return "macwindow.on.rectangle"
        case .settings: return "slider.horizontal.3"
        case .diagnostics: return "terminal"
        }
    }
}

struct ContentView: View {
    @Bindable var state: AppState
    @State private var selectedTab: SidebarTab = .library

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SidebarTab.allCases, selection: $selectedTab) { tab in
                    HStack {
                        Label(tab.rawValue, systemImage: tab.symbol)
                        Spacer()
                        if tab == .windows && !state.activeWindows.isEmpty {
                            Text("\(state.activeWindows.count)")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                        }
                    }
                    .tag(tab)
                }
                .listStyle(.sidebar)

                Divider()

                engineFooter
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if let message = state.bannerMessage {
                    bannerBar(message: message, isError: state.bannerIsError)
                    Divider()
                }

                if !state.runtimeStatus.isReadyToBoot {
                    SetupView(state: state)
                } else {
                    switch selectedTab {
                    case .library:
                        LibraryView(state: state)
                    case .windows:
                        WindowsView(state: state)
                    case .settings:
                        SettingsView(state: state)
                    case .diagnostics:
                        DiagnosticsView(state: state)
                    }
                }
            }
            .frame(minWidth: 640, minHeight: 500)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if state.runtimeStatus.isReadyToBoot {
                    Button {
                        Task { await state.launchFullDeviceScreen() }
                    } label: {
                        Label("Device Screen", systemImage: "iphone")
                    }
                    .help("Open full Android home screen")
                    .disabled(state.engineState.isBusy)

                    if state.engineState.isRunning {
                        Button {
                            Task { await state.stopEngine() }
                        } label: {
                            Label("Stop Engine", systemImage: "stop.fill")
                        }
                        .help("Gracefully save snapshot and stop Android VM")
                    } else {
                        Button {
                            Task { await state.startEngine() }
                        } label: {
                            Label("Start Engine", systemImage: "play.fill")
                        }
                        .disabled(state.engineState.isBusy)
                        .help("Start headless Apple Silicon Android VM")
                    }
                }
            }
        }
        .task {
            await state.bootstrapOnLaunch()
        }
    }

    private var engineFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                Text(state.engineState.statusLabel)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text("\(state.config.cpuCores) cores · \(state.config.ramMB / 1024) GB RAM · \(state.config.gpuMode == .host ? "Metal" : "CPU")")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusDotColor: Color {
        switch state.engineState {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .error: return .red
        case .stopped: return .secondary.opacity(0.5)
        }
    }

    private func bannerBar(message: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.red : Color.green)
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
            Button {
                state.clearBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
    }
}
