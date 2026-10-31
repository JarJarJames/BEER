import Foundation
import SwiftUI

/// Remembers the PID of the live presence helper so a BEER that died without
/// unwinding can clean it up next launch.
///
/// Belt-and-braces: the helper already exits when BEER's end of its stdin pipe
/// closes, which covers even a force quit. This catches the remainder — a
/// helper wedged on a dead socket, say.
enum PlaySessionRegistry {
    struct Record: Codable {
        let pid: Int32
        /// The BEER that started the helper. Nil in records written before
        /// this was tracked, which can only be from an earlier run.
        var owner: Int32?
    }

    static func record(pid: Int32) {
        // Without the record, a helper BEER loses track of can't be swept.
        attempt("record the presence helper's PID", log: Log.session) {
            try AppPaths.ensureBaseDirectories()
            let record = Record(pid: pid, owner: getpid())
            try JSONEncoder().encode(record).write(to: AppPaths.playSessionStateURL, options: .atomic)
        }
    }

    /// A helper this BEER started is live, not left behind. The sweep runs
    /// alongside sign-in at launch, so it can find this run's own record —
    /// and killing that helper silently ended play-time tracking.
    static func isOrphan(_ record: Record, currentPID: Int32 = getpid()) -> Bool {
        record.owner != currentPID
    }

    static func clear() {
        attempt("clear the presence helper's PID record", log: Log.session) {
            try FileManager.default.removeItemIfPresent(at: AppPaths.playSessionStateURL)
        }
    }

    /// Stop a helper left behind by a previous run. Confirms the PID still
    /// belongs to a CloudSync process before signalling it — PIDs get recycled,
    /// and killing an unrelated process would be far worse than leaving a stale
    /// status behind.
    static func sweepOrphans() async {
        guard let data = try? Data(contentsOf: AppPaths.playSessionStateURL),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              isOrphan(record) else { return }
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
