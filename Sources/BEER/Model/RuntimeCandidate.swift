import Foundation

struct RuntimeCandidate: Identifiable, Codable, Hashable {
    var id: String { bundlePath ?? executablePath }
    var kind: RuntimeKind
    var executablePath: String
    var displayName: String
    var bundlePath: String? = nil
    var version: String? = nil
    var entrypoints: RuntimeEntrypoints? = nil

    var parentDirectory: String {
        URL(fileURLWithPath: executablePath).deletingLastPathComponent().path
    }

    var locationPath: String {
        bundlePath ?? executablePath
    }
}
