import Foundation
import SwiftUI

/// Remembers the PID of the live presence helper so a BEER that died without
/// unwinding can clean it up next launch.
///
/// Belt-and-braces: the helper already exits when BEER's end of its stdin pipe
/// closes, which covers even a force quit. This catches the remainder — a
/// helper wedged on a dead socket, say.
enum PlaySessionRegistry {
    private struct Record: Codable { let pid: Int32 }

    static func record(pid: Int32) {
        try? AppPaths.ensureBaseDirectories()
        guard let data = try? JSONEncoder().encode(Record(pid: pid)) else { return }
        try? data.write(to: AppPaths.playSessionStateURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: AppPaths.playSessionStateURL)
    }

    /// Stop a helper left behind by a previous run. Confirms the PID still
    /// belongs to a CloudSync process before signalling it — PIDs get recycled,
    /// and killing an unrelated process would be far worse than leaving a stale
    /// status behind.
    static func sweepOrphans() async {
        guard let data = try? Data(contentsOf: AppPaths.playSessionStateURL),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return }
        clear()

        guard let result = try? await ShellRunner.run(
            executable: "/bin/ps",
            arguments: ["-p", "\(record.pid)", "-o", "comm="],
            environment: [:],
            outputHandler: { _ in }
        ), result.exitCode == 0, result.output.contains("CloudSync") else { return }

        kill(record.pid, SIGTERM)
    }
}
