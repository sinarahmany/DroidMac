import SwiftUI
import AppKit
import DroidMacCore

struct WindowsView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Running Native Windows")
                        .font(.title2.weight(.semibold))
                    Text("Each Android app or game runs in its own isolated virtual display and native macOS window.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        Task { await state.launchFullDeviceScreen() }
                    } label: {
                        Label("Full Android Screen", systemImage: "iphone.gen3")
                    }
                    Button {
                        pickFileToTransfer()
                    } label: {
                        Label("Send File", systemImage: "arrow.up.doc")
                    }
                    .disabled(!state.engineState.isRunning)
                }
            }
            .padding(20)

            Divider()

            if state.activeWindows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No Active App Windows")
                        .font(.headline)
                    Text("Launch an app from the Library or open the full Android screen to browse Play Store and system settings.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                List {
                    ForEach(state.activeWindows) { session in
                        HStack(spacing: 12) {
                            Image(systemName: session.profile?.sfSymbol ?? "iphone")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .font(.body.weight(.medium))
                                HStack(spacing: 8) {
                                    if let pkg = session.packageName {
                                        Text(pkg)
                                    } else {
                                        Text("Primary Android Display")
                                    }
                                    Text("·")
                                    Text("PID \(session.pid)")
                                        .monospacedDigit()
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Close Window", role: .destructive) {
                                Task { await state.closeWindow(session.id) }
                            }
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func pickFileToTransfer() {
        let panel = NSOpenPanel()
        panel.title = "Send File to Android Downloads"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await state.pushFileToAndroid(from: url) }
        }
    }
}
