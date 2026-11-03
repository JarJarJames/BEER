import Foundation

/// A game folder on a drive that no bottle uses: one removed while its drive
/// was unplugged, or one from another Mac or an earlier BEER.
struct FoundGame: Identifiable, Equatable, Sendable {
    let folder: URL
    let marker: GameFolderMarker
    let drive: InstallVolume
    /// Nil when the folder has no .exe BEER can find.
    let launchExecutable: URL?
    /// Why it can't be added; nil when it can.
    let blockedReason: String?

    var id: String { folder.path }
    var canAdd: Bool { blockedReason == nil }
}
