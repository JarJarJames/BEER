import Foundation

extension String {
    var safePathComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}
