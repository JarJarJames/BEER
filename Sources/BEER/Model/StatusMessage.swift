import Foundation

/// A short outcome banner — the text plus whether it reads as a failure. Keeps
/// a message and its red/green flag in one value instead of two properties that
/// have to be assigned in step at every site.
enum StatusMessage: Equatable {
    case success(String)
    case failure(String)

    var text: String {
        switch self {
        case .success(let t), .failure(let t): return t
        }
    }

    var isError: Bool {
        if case .failure = self { return true }
        return false
    }
}
