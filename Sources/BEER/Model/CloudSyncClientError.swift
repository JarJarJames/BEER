import Foundation

enum CloudSyncClientError: LocalizedError {
    case helperMissing
    case helper(String)
    case authExpired
    case rateLimited
    case badOutput(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "The CloudSync helper isn't installed. Build it with Tools/CloudSync (see scripts/build_cloudsync.sh)."
        case .helper(let msg):
            return "Steam Cloud error: \(msg)"
        case .authExpired:
            return "Your Steam sign-in expired or was revoked. Reconnect to keep syncing — your local saves are untouched."
        case .rateLimited:
            return "Steam is temporarily rate-limiting sign-ins for your account (too many recent logins). Wait a few minutes, then try again — don't re-sign-in, that only extends the cooldown. Your saves are safe."
        case .badOutput(let detail):
            return "Couldn't understand the CloudSync helper's output: \(detail.prefix(1500)). The helper may be out of date; rebuild BEER so the app and helper versions match."
        }
    }
}
