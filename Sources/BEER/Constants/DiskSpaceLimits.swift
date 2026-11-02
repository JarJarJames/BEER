import Foundation

/// How much free space an install must leave behind. Bottles keep growing after
/// install (Wine files, shader caches) and so do save backups, so a download is
/// refused unless it fits with room to spare.
enum DiskSpaceLimits {
    /// Kept free on top of what Steam says the game needs.
    static let safetyMarginBytes: Int64 = 5 * 1024 * 1024 * 1024

    /// A runtime archive unpacks to several times its download size, and the
    /// archive stays on disk while it extracts.
    static let runtimeExtractionFactor: Int64 = 5
}
