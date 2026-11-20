import SwiftUI
import AppKit
import DroidMacCore

struct DiagnosticsView: View {
    @Bindable var state: AppState
    @State private var filterLevel: LogLevel? = nil

    private var filteredLogs: [LogEntry] {
        guard let filterLevel else { return state.logs }
        return state.logs.filter { $0.level == filterLevel }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Diagnostics & Logs")
                    .font(.title2.weight(.semibold))

                Spacer()

                Picker("Level", selection: $filterLevel) {
                    Text("All").tag(Optional<LogLevel>.none)
                    Text("Info").tag(Optional<LogLevel>.some(.info))
                    Text("Warnings").tag(Optional<LogLevel>.some(.warning))
                    Text("Errors").tag(Optional<LogLevel>.some(.error))
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Button("Copy Logs") {
                    copyLogs()
                }
                .disabled(state.logs.isEmpty)

                Button("Clear") {
                    state.logs.removeAll()
                }
                .disabled(state.logs.isEmpty)
            }
            .padding(16)

            Divider()

            if case .running(let serial, let version, let gpu) = state.engineState {
                HStack(spacing: 20) {
                    Label("Serial: \(serial)", systemImage: "cable.connector")
                    Label("Android \(version)", systemImage: "cpu")
                    Label("GPU: \(gpu)", systemImage: "display")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLogs) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                                Text(entry.level.rawValue)
                                    .foregroundStyle(color(for: entry.level))
                                    .frame(width: 44, alignment: .leading)
                                Text("[\(entry.source)]")
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .id(entry.id)
                        }
                    }
                    .padding(14)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: state.logs.count) { _, _ in
                    if let last = filteredLogs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        case .debug: return .gray
        }
    }

    private func copyLogs() {
        let text = filteredLogs.map { entry in
            "\(entry.timestamp.ISO8601Format()) [\(entry.level.rawValue)][\(entry.source)] \(entry.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
