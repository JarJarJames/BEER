import Foundation

struct RuntimeRelease: Equatable {
    let family: RuntimeFamily
    let tag: String
    let name: String
    let assetName: String
    let assetURL: URL
    let size: Int64
    let digest: String?
    let htmlURL: URL

    var displaySize: String {
        size.fileSizeString
    }

    /// Directory under Runtimes/ to extract into. Kept distinct per family so
    /// GPTK and mainline-Wine builds never collide.
    var installDirName: String {
        switch family {
        case .gptk: return "GPTK-\(tag.safePathComponent)"
        case .wine: return assetName.replacingOccurrences(of: ".tar.xz", with: "").safePathComponent
        }
    }

    /// Display name the runtime scanner attaches (shown in the per-game picker).
    var managedDisplayName: String {
        switch family {
        case .gptk: return "Managed GPTK \(tag)"
        case .wine: return "Managed " + assetName
            .replacingOccurrences(of: "-osx64.tar.xz", with: "")
            .replacingOccurrences(of: "wine-", with: "Wine ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
        }
    }
}
