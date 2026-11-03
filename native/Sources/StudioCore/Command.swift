import Foundation
import Darwin

public struct CommandResult {
    public let status: Int32
    public let output: String
    public let timedOut: Bool
    public let cancelled: Bool
}

/// Owned processes only. No global killall; output is drained continuously.
public final class Command: @unchecked Sendable {
    public init() {}
    private let lock = NSLock()
    private var cancelled = false
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    public func run(_ path: String, _ args: [String], timeout: TimeInterval,
             onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = pipe
                process.standardError = pipe
                var output = Data()
                var expired = false
                let started = Date()
                do {
                    try process.run()
                    try? pipe.fileHandleForWriting.close()
                    let fd = pipe.fileHandleForReading.fileDescriptor
                    _ = fcntl(fd, F_SETFL, O_NONBLOCK)
                    var stopTime: Date?
                    while true {
                        var bytes = [UInt8](repeating: 0, count: 8192)
                        let count = read(fd, &bytes, bytes.count)
                        if count > 0 {
                            let data = Data(bytes.prefix(count))
                            output.append(data)
                            onOutput(String(decoding: data, as: UTF8.self))
                        }
                        if !process.isRunning && count <= 0 { break }
                        if (self.isCancelled || Date().timeIntervalSince(started) > timeout) && stopTime == nil {
                            expired = !self.isCancelled
                            stopTime = Date()
                            if process.isRunning { process.terminate() }
                        }
                        if let stop = stopTime, Date().timeIntervalSince(stop) > 3, process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                        if count <= 0 { Thread.sleep(forTimeInterval: 0.05) }
                    }
                    process.waitUntilExit()
                    try? pipe.fileHandleForReading.close()
                    continuation.resume(returning: CommandResult(status: process.terminationStatus,
                        output: String(decoding: output, as: UTF8.self), timedOut: expired, cancelled: self.isCancelled))
                } catch {
                    try? pipe.fileHandleForReading.close()
                    try? pipe.fileHandleForWriting.close()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
