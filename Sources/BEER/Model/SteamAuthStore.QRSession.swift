import Foundation

extension SteamAuthStore {
    /// What the QR sheet renders. The helper hands us a fresh challenge URL
    /// each time Steam rotates it (~every 30s).
    struct QRSession {
        let challengeURL: String
    }
}
