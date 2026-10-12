import Foundation

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// Reassembles chunks that split a line in half, then emits complete lines.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""

    func append(_ chunk: String, emit: @Sendable (String) -> Void) {
        let lines = lock.withLock { () -> [String] in
            pending.append(chunk)
            var ready: [String] = []
            while let newline = pending.firstIndex(of: "\n") {
                let line = String(pending[..<newline])
                pending.removeSubrange(...newline)
                ready.append(line)
            }
            return ready
        }
        for line in lines where !line.isEmpty {
            emit(line + "\n")
        }
    }

    func finish(emit: @Sendable (String) -> Void) {
        let rest = lock.withLock { () -> String in
            let value = pending
            pending = ""
            return value
        }
        if !rest.isEmpty {
            emit(rest + "\n")
        }
    }
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func capture(executable: String, arguments: [String]) async throws -> CommandOutput {
        try await runProcess(executable: executable, arguments: arguments, stream: nil)
    }

    public func run(
        executable: String,
        arguments: [String],
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> Int {
        let output = try await runProcess(executable: executable, arguments: arguments, stream: onOutput)
        return output.status
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        stream: (@Sendable (String) -> Void)?
    ) async throws -> CommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.environment = ToolEnvironment.environment(forExecutable: executable)

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    let stdoutBox = LockedData()
                    let stderrBox = LockedData()
                    let stdoutLines = LineBuffer()
                    let stderrLines = LineBuffer()
                    let group = DispatchGroup()

                    // Read both pipes on background threads before the process starts.
                    // Waiting for exit first fills the pipe buffer and deadlocks brew.
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        Self.drain(
                            stdoutPipe.fileHandleForReading,
                            into: stdoutBox,
                            lines: stream == nil ? nil : stdoutLines,
                            stream: stream
                        )
                        group.leave()
                    }

                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        Self.drain(
                            stderrPipe.fileHandleForReading,
                            into: stderrBox,
                            lines: stream == nil ? nil : stderrLines,
                            stream: stream
                        )
                        group.leave()
                    }

                    try process.run()
                    process.waitUntilExit()
                    group.wait()

                    let stderr = String(data: stderrBox.snapshot(), encoding: .utf8) ?? ""
                    continuation.resume(
                        returning: CommandOutput(
                            status: Int(process.terminationStatus),
                            stdout: stdoutBox.snapshot(),
                            stderr: stderr
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func drain(
        _ handle: FileHandle,
        into box: LockedData,
        lines: LineBuffer?,
        stream: (@Sendable (String) -> Void)?
    ) {
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            box.append(chunk)
            if let lines, let stream, let text = String(data: chunk, encoding: .utf8) {
                lines.append(text, emit: stream)
            }
        }
        if let lines, let stream {
            lines.finish(emit: stream)
        }
    }
}
