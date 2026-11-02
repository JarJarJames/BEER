import Foundation

/// User-facing text for an install refused for lack of disk space.
enum DiskSpaceStrings {
    static let alertTitle = "Not enough disk space"
    static let okButton = "OK"
    static let unknownSize = "Steam doesn't list this game's size, so free space wasn't checked."

    static func shortfall(_ s: DiskSpaceShortfall) -> String {
        "Needs about \(format(s.neededBytes)), and \(s.volumeName) has \(format(s.availableBytes)) free. Free up \(format(s.missingBytes)) and try again."
    }

    static func sizeCheckFailed(_ reason: String) -> String {
        "Couldn't ask Steam for this game's size (\(reason)), so free space wasn't checked."
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
