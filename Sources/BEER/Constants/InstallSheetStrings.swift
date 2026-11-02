import Foundation

/// User-facing text for the sheet shown before a game downloads.
enum InstallSheetStrings {
    static let title = "Install"
    static let installTo = "INSTALL TO:"
    static let installButton = "Install"
    static let cancelButton = "Cancel"
    static let checking = "Checking size…"
    static let unknownSize = "Size unknown"
    static let unknownVolume = "Free space unknown"

    static func size(_ bytes: Int64) -> String { format(bytes) }

    static func free(_ bytes: Int64) -> String { "\(format(bytes)) FREE" }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
