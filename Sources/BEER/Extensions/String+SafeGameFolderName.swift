import Foundation

extension String {
    /// A game's name as a folder name under a bottle's `drive_c/Games`.
    var safeGameFolderName: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        let mapped = unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_ .")).ifEmpty(default: "Game")
    }

    /// This folder name as Windows sees it. Windows drops trailing dots and
    /// spaces, so Wine can't open anything inside "Easy Delivery Co." — it
    /// looks for "Easy Delivery Co" instead.
    var windowsFolderName: String {
        var name = Substring(self)
        while let last = name.last, last == "." || last == " " { name = name.dropLast() }
        return String(name)
    }
}
