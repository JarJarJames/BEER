import Foundation

extension Int64 {
    var fileSizeString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
