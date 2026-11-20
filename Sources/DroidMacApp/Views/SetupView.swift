import SwiftUI
import DroidMacCore

struct SetupView: View {
    @Bindable var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set Up Android Runtime")
                        .font(.largeTitle.weight(.semibold))
                    Text("DroidMac runs an isolated ARM64 Android 15 virtual machine powered by Apple Hypervisor and Metal GPU acceleration—no root access or system modifications required.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 0) {
                    preflightRow(
                        title: "Apple Silicon Architecture",
                        detail: state.runtimeStatus.isAppleSilicon ? "ARM64 native virtualization ready" : "Detected \(state.runtimeStatus.architecture)",
                        ok: state.runtimeStatus.isAppleSilicon
                    )
                    Divider()
                    preflightRow(
                        title: "OpenJDK 21",
                        detail: state.runtimeStatus.javaPath ?? "Not installed (brew install openjdk@21)",
                        ok: state.runtimeStatus.javaPath != nil
                    )
                    Divider()
                    preflightRow(
                        title: "Android Command-Line & Platform Tools",
                        detail: state.runtimeStatus.adbPath ?? "Not installed (brew install --cask android-commandlinetools android-platform-tools)",
                        ok: state.runtimeStatus.sdkManagerPath != nil && state.runtimeStatus.adbPath != nil
                    )
                    Divider()
                    preflightRow(
                        title: "Native Window Renderer (scrcpy)",
                        detail: state.runtimeStatus.scrcpyPath ?? "Not installed (brew install scrcpy)",
                        ok: state.runtimeStatus.scrcpyPath != nil
                    )
                    Divider()
                    preflightRow(
                        title: "Android Emulator & ARM64 System Image",
                        detail: (state.runtimeStatus.emulatorPath != nil && state.runtimeStatus.systemImageInstalled)
                            ? state.config.systemImage.displayName
                            : "Will be downloaded into ~/Library/Application Support/DroidMac",
                        ok: state.runtimeStatus.emulatorPath != nil && state.runtimeStatus.systemImageInstalled
                    )
                    Divider()
                    preflightRow(
                        title: "Virtual Device Profile",
                        detail: state.runtimeStatus.avdExists ? state.config.avdName : "Will be created & tuned for Apple Metal",
                        ok: state.runtimeStatus.avdExists
                    )
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))

                HStack(spacing: 12) {
                    Button {
                        Task { await state.runSetup() }
                    } label: {
                        HStack(spacing: 8) {
                            if state.isSettingUp {
                                ProgressView().controlSize(.small)
                            }
                            Text(state.isSettingUp ? "Installing Runtime…" : "Install & Configure Runtime")
                        }
                        .frame(minWidth: 210)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.isSettingUp || !state.runtimeStatus.hasCoreTools)

                    Button("Re-check Environment") {
                        state.refreshRuntimeStatus()
                    }
                    .controlSize(.large)
                    .disabled(state.isSettingUp)
                }

                if !state.runtimeStatus.hasCoreTools {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Install missing Homebrew prerequisites first:")
                            .font(.subheadline.weight(.medium))
                        Text("brew install openjdk@21 scrcpy && brew install --cask android-commandlinetools android-platform-tools")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                if !state.logs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Setup Activity")
                            .font(.headline)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(state.logs.suffix(40)) { entry in
                                    Text("[\(entry.source)] \(entry.message)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(entry.level == .error ? .red : .secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(10)
                        }
                        .frame(height: 150)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func preflightRow(title: String, detail: String, ok: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
