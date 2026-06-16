import Foundation

struct ProcessResult {
    let exitCode: Int32
    let output: String
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ chunk: String) {
        lock.lock()
        storage += chunk
        lock.unlock()
    }

    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

enum ShellRunner {
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil,
        outputHandler: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            process.currentDirectoryURL = currentDirectory

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let buffer = OutputBuffer()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                buffer.append(chunk)
                outputHandler(chunk)
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: ProcessResult(exitCode: process.terminationStatus, output: buffer.output))
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
