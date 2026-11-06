import Foundation

/// User-facing text for the sheet shown before a game downloads.
enum InstallSheetStrings {
    static let title = "Install"
    static let installTo = "INSTALL TO:"
    static let installButton = "Install"
    static let cancelButton = "Cancel"
    static let unknownSize = "Size unknown"
    static func dlc(included: Int, of total: Int) -> String { "DLC: \(included) of \(total)" }

    static func size(_ bytes: Int64) -> String { format(bytes) }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
