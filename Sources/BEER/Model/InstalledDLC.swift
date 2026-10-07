import Foundation

/// One DLC the user has turned on for a game. Some DLC (season passes,
/// artbooks) carry no depot at all — those are declared to the emulator but
/// have no files on disk.
struct InstalledDLC: Codable, Hashable, Identifiable {
    var id: Int { appID }
    var appID: Int
    var name: String
    var installedAt: Date

    /// The emulator's ini parser reads to end-of-line, so a name carrying a
    /// newline would corrupt the following entries.
    var iniSafeName: String {
        name.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
