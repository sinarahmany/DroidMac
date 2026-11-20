import SwiftUI
import AppKit
import DroidMacCore

@MainActor
final class DroidMacAppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.shutdownSynchronouslyForQuit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct DroidMacApplication: App {
    @NSApplicationDelegateAdaptor(DroidMacAppDelegate.self) private var delegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("DroidMac") {
            ContentView(state: state)
                .onAppear {
                    delegate.appState = state
                }
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Engine") {
                Button("Start Android Engine") {
                    Task { await state.startEngine() }
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(state.engineState.isRunning || state.engineState.isBusy || !state.runtimeStatus.isReadyToBoot)

                Button("Stop Android Engine") {
                    Task { await state.stopEngine() }
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!state.engineState.isRunning)

                Divider()

                Button("Open Full Android Screen") {
                    Task { await state.launchFullDeviceScreen() }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!state.runtimeStatus.isReadyToBoot)

                Button("Open Google Play Store") {
                    Task { await state.launchPlayStore() }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!state.runtimeStatus.isReadyToBoot)

                Divider()

                Button("Refresh Apps") {
                    Task { await state.refreshApps() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!state.engineState.isRunning)
            }
        }
    }
}
