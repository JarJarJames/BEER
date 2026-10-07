import Foundation

enum SteamAuthError: LocalizedError {
    case notSignedIn
    case canceled
    case helper(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Steam Cloud yet — click Connect first."
        case .canceled:
            return "Sign-in canceled."
        case .helper(let msg):
            return msg
        }
    }
}
