import Foundation

/// The drive a game's files were put on, recorded with the game so it can be
/// found again after the drive is renamed, and named while it's unplugged.
struct GameDrive: Codable, Hashable, Sendable {
    var uuid: String
    /// The name it had when last seen, for "Connect <name> to play".
    var name: String
    /// Where it was mounted when last seen, so stored paths can be moved to
    /// wherever it's mounted now.
    var mountPath: String

    /// `path` as it reads with the drive mounted at `newRoot` instead. Nil when
    /// `path` isn't on this drive.
    func rebase(_ path: String, onto newRoot: URL) -> String? {
        let old = URL(fileURLWithPath: mountPath).standardizedFileURL.path
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized.hasPrefix(old + "/") else { return nil }
        return newRoot.appendingPathComponent(String(standardized.dropFirst(old.count + 1))).path
    }
}
