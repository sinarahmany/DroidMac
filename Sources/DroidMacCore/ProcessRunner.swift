import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }
}

public final class ProcessRunner: Sendable {
    public init() {}

    /// Executes an executable with explicit arguments (never via `/bin/sh -c`) and captures stdout/stderr.
    public func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        standardInput: Data? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            if let environment {
                process.environment = environment
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var stdinPipe: Pipe?
            if standardInput != nil {
                let pipe = Pipe()
                process.standardInput = pipe
                stdinPipe = pipe
            } else {
                process.standardInput = FileHandle.nullDevice
            }

            final class PipeAccumulator: @unchecked Sendable {
                private let lock = NSLock()
                var stdout = Data()
                var stderr = Data()
                var resumed = false

                func appendStdout(_ data: Data) {
                    lock.lock()
                    stdout.append(data)
                    lock.unlock()
                }

                func appendStderr(_ data: Data) {
                    lock.lock()
                    stderr.append(data)
                    lock.unlock()
                }

                func tryResume() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if resumed { return false }
                    resumed = true
                    return true
                }

                func snapshot() -> (String, String) {
                    lock.lock()
                    defer { lock.unlock() }
                    return (
                        String(data: stdout, encoding: .utf8) ?? "",
                        String(data: stderr, encoding: .utf8) ?? ""
                    )
                }
            }

            let accumulator = PipeAccumulator()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    accumulator.appendStdout(data)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    accumulator.appendStderr(data)
                }
            }

            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { proc in
                timer.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let remainingOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if !remainingOut.isEmpty { accumulator.appendStdout(remainingOut) }
                let remainingErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !remainingErr.isEmpty { accumulator.appendStderr(remainingErr) }

                if accumulator.tryResume() {
                    let (outStr, errStr) = accumulator.snapshot()
                    continuation.resume(returning: ProcessResult(
                        exitCode: proc.terminationStatus,
                        stdout: outStr,
                        stderr: errStr
                    ))
                }
            }

            do {
                try process.run()
                timer.resume()
                if let inputData = standardInput, let pipe = stdinPipe {
                    DispatchQueue.global(qos: .utility).async {
                        pipe.fileHandleForWriting.write(inputData)
                        try? pipe.fileHandleForWriting.close()
                    }
                }
            } catch {
                timer.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if accumulator.tryResume() {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Runs a command streaming output line by line to `onLine`.
    public func runStreaming(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        standardInput: Data? = nil,
        onLine: @escaping @Sendable (String, Bool) -> Void
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            if let environment {
                process.environment = environment
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var stdinPipe: Pipe?
            if standardInput != nil {
                let pipe = Pipe()
                process.standardInput = pipe
                stdinPipe = pipe
            } else {
                process.standardInput = FileHandle.nullDevice
            }

            func attachHandler(_ pipe: Pipe, isError: Bool) {
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                    for line in chunk.split(whereSeparator: \.isNewline) {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onLine(trimmed, isError)
                        }
                    }
                }
            }

            attachHandler(stdoutPipe, isError: false)
            attachHandler(stderrPipe, isError: true)

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
                if let inputData = standardInput, let pipe = stdinPipe {
                    DispatchQueue.global(qos: .utility).async {
                        pipe.fileHandleForWriting.write(inputData)
                        try? pipe.fileHandleForWriting.close()
                    }
                }
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Spawns a long-running background process (like `emulator` or `scrcpy`) and streams its logs.
    public func spawn(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        onLine: (@Sendable (String, Bool) -> Void)? = nil,
        onExit: (@Sendable (Int32) -> Void)? = nil
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let onLine {
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.split(whereSeparator: \.isNewline) {
                    let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { onLine(s, false) }
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.split(whereSeparator: \.isNewline) {
                    let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { onLine(s, true) }
                }
            }
        } else {
            // Drain pipes to avoid SIGPIPE/buffer stalls
            stdoutPipe.fileHandleForReading.readabilityHandler = { _ = $0.availableData }
            stderrPipe.fileHandleForReading.readabilityHandler = { _ = $0.availableData }
        }

        process.terminationHandler = { proc in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            onExit?(proc.terminationStatus)
        }

        try process.run()
        return process
    }

    /// Spawns a detached background process redirecting stdout/stderr to a log file so it safely outlives short-lived CLI callers.
    public func spawnDetached(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        logFileURL: URL
    ) throws -> Process {
        let fm = FileManager.default
        try fm.createDirectory(at: logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logFileURL.path) {
            fm.createFile(atPath: logFileURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logFileURL)
        try logHandle.truncate(atOffset: 0)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        return process
    }
}
