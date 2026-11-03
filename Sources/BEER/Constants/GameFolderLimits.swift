import Foundation

/// Numbers for copying and naming game folders.
enum GameFolderLimits {
    /// "Game", "Game 2", … before falling back to a random suffix.
    static let maxNumberedNames = 99
    /// Copies are read and written in pieces this big, so progress moves and
    /// Cancel works during a single multi-gigabyte file.
    static let copyChunkBytes = 8 * 1024 * 1024
    /// Files up to this size are compared byte for byte after a copy, which
    /// covers save files. Bigger ones (game data) are compared by size.
    static let byteCompareLimitBytes: Int64 = 64 * 1024 * 1024
}
