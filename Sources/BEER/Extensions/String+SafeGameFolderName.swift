import Foundation

extension String {
    /// A game's name as a folder name under a bottle's `drive_c/Games`.
    var safeGameFolderName: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        let mapped = unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_ ")).ifEmpty(default: "Game")
    }
}
