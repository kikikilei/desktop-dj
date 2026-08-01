import Darwin
import Foundation

struct ProcessExecutionResult: Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32?
    let duration: TimeInterval
    let timedOut: Bool
    let launchError: String?
}

final class ProcessRunner: @unchecked Sendable {
    private let stdoutLimit: Int
    private let stderrLimit: Int

    init(stdoutLimit: Int = 8 * 1_024 * 1_024, stderrLimit: Int = 64 * 1_024) {
        self.stdoutLimit = stdoutLimit
        self.stderrLimit = stderrLimit
    }

    func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> ProcessExecutionResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let output = BoundedDataBuffer(limit: stdoutLimit)
        let errors = BoundedDataBuffer(limit: stderrLimit)
        let readers = DispatchGroup()
        let terminated = DispatchSemaphore(value: 0)
        let startedAt = Date()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { _ in terminated.signal() }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            return ProcessExecutionResult(
                stdout: Data(),
                stderr: Data(),
                exitCode: nil,
                duration: Date().timeIntervalSince(startedAt),
                timedOut: false,
                launchError: error.localizedDescription
            )
        }

        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()
        drain(outputPipe.fileHandleForReading, into: output, group: readers)
        drain(errorPipe.fileHandleForReading, into: errors, group: readers)

        var timedOut = false
        if terminated.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if terminated.wait(timeout: .now() + 0.25) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 1)
            }
        }

        _ = readers.wait(timeout: .now() + 1)
        return ProcessExecutionResult(
            stdout: output.snapshot(),
            stderr: errors.snapshot(),
            exitCode: process.isRunning ? nil : process.terminationStatus,
            duration: Date().timeIntervalSince(startedAt),
            timedOut: timedOut,
            launchError: nil
        )
    }

    private func drain(
        _ handle: FileHandle,
        into buffer: BoundedDataBuffer,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            while true {
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                buffer.append(chunk)
            }
        }
    }
}

private final class BoundedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - data.count)
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
