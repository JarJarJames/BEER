import Foundation

/// What a library card's corner badge says. A download in progress wins over
/// everything else, since it's what the player is waiting on.
enum LibraryCardBadge: Equatable {
    case installed
    case update
    case driveMissing
    case downloading(Double)
    case paused(Double)
    /// A bottle with no game in it yet: a download that failed or was cut off.
    case notInstalled

    /// `isComplete` is false while the bottle has no launch executable, i.e.
    /// its download never finished. Nil for a game that has nothing to show.
    static func resolve(
        isInstalled: Bool, isComplete: Bool, isDriveMissing: Bool, hasUpdate: Bool,
        download: DownloadsStore.Entry?
    ) -> LibraryCardBadge? {
        if let download, download.isActive { return .downloading(download.fraction) }
        if let download, download.isPaused { return .paused(download.fraction) }
        guard isInstalled else { return nil }
        if isDriveMissing { return .driveMissing }
        if !isComplete { return .notInstalled }
        return hasUpdate ? .update : .installed
    }

    var text: String {
        switch self {
        case .installed: return "INSTALLED"
        case .update: return GameUpdateStrings.cardBadge
        case .driveMissing: return InstallDriveStrings.cardBadge
        case .downloading(let fraction): return DownloadsStrings.cardDownloading(fraction)
        case .paused(let fraction): return DownloadsStrings.cardPaused(fraction)
        case .notInstalled: return DownloadsStrings.cardNotInstalled
        }
    }

    /// The symbol a narrow card shows instead of the words, with the percent
    /// for a download. Nil where the words are short enough to keep.
    var compactSymbol: String? {
        switch self {
        case .downloading: return "arrow.down"
        case .paused: return "pause.fill"
        case .driveMissing: return "externaldrive.badge.xmark"
        default: return nil
        }
    }

    /// How far along, for the badge's fill. Nil for a badge with no progress.
    var fraction: Double? {
        switch self {
        case .downloading(let fraction), .paused(let fraction): return fraction
        default: return nil
        }
    }
}
