import Foundation

enum RuntimeBundleError: LocalizedError {
    case notDirectory
    case missingExecutable(String)

    var errorDescription: String? {
        switch self {
        case .notDirectory:
            "The selected runtime is not a directory bundle."
        case .missingExecutable(let path):
            "The selected runtime bundle references a missing or non-executable file: \(path)"
        }
    }
}
