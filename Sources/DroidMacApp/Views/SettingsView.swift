import SwiftUI
import DroidMacCore

struct SettingsView: View {
    @Bindable var state: AppState

    private let maxHostCores = max(ProcessInfo.processInfo.processorCount, 4)

    var body: some View {
        Form {
            Section("Virtual Machine Hardware") {
                Stepper(value: $state.config.cpuCores, in: 2...min(maxHostCores, 10)) {
                    HStack {
                        Text("CPU Cores")
                        Spacer()
                        Text("\(state.config.cpuCores) cores")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Picker("Memory (RAM)", selection: $state.config.ramMB) {
                    Text("3 GB (Light Apps)").tag(3072)
                    Text("4 GB (Recommended)").tag(4096)
                    Text("6 GB (Heavy 3D Games)").tag(6144)
                    Text("8 GB (Max Gaming)").tag(8192)
                }

                Picker("GPU Acceleration", selection: $state.config.gpuMode) {
                    ForEach(GPUMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Text(state.config.gpuMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Quick Boot Snapshots (fast 2–4s resume)", isOn: $state.config.enableQuickBoot)
            }

            Section("Native Window & Gaming") {
                Picker("Frame Rate Limit", selection: $state.config.maxFPS) {
                    Text("30 FPS (Battery Saver)").tag(30)
                    Text("60 FPS (Smooth)").tag(60)
                    Text("90 FPS").tag(90)
                    Text("120 FPS (ProMotion)").tag(120)
                }

                Toggle("Forward Android Audio to macOS CoreAudio", isOn: $state.config.enableAudio)
                Toggle("Apple VideoToolbox Hardware Decode", isOn: $state.config.enableHardwareDecode)
                Toggle("Dynamic Reflow Resize (Flex Display)", isOn: $state.config.enableFlexDisplay)
                Text("Off (default) uses crisp 2× Retina scaling with zero crop; On dynamically reflows Android app layouts as you drag-resize the window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Forward Game Controllers (PS / Xbox via UHID)", isOn: $state.config.enableGamepad)
                Toggle("Hide Android Navigation Bar in Native Window Mode", isOn: $state.config.hideSystemDecorationsInAppMode)
            }

            Section("Security & Isolation") {
                LabeledContent("Virtualization") {
                    Text("Apple Hypervisor.framework (Unprivileged User Space)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Host Disk Access") {
                    Text("Isolated — Explicit Transfer to /sdcard/Download Only")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("ADB Binding") {
                    Text("127.0.0.1 Loopback (\(state.config.emulatorSerial))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                LabeledContent("Mac App Launchers") {
                    Button("Reveal in Finder") {
                        state.openLaunchersFolderInFinder()
                    }
                }
                LabeledContent("Managed Runtime Data") {
                    Button("Reveal in Finder") {
                        state.openSDKFolderInFinder()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: state.config) { _, _ in
            state.saveConfig()
        }
    }
}
