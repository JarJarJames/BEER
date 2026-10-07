import Foundation

// Steam Cloud authentication, driven by the native CloudSync helper (SteamKit2).
//
// Why the helper owns auth: the Cloud client protocol only accepts a refresh
// token with the "SteamClient" audience. SteamKit2's QR flow mints exactly
// that. (An earlier pure-Swift QR flow requested website_id="Client", which
// made Steam hand back a *web*-audience token — rejected by the cloud client
// API as InvalidPassword.) The helper streams the challenge URL as it rotates,
// and finally the account name + refresh token, which we persist here.
//
// The token is the user's Steam credential, so it lives in the macOS Keychain
// (see `Keychain`), encrypted at rest and gated on login — not in a readable
// file. Installs that predate this still have a plaintext `steam-cloud-auth.json`
// from older builds; `load()` migrates it into the Keychain and deletes it.

@MainActor
final class SteamAuthStore: ObservableObject {
    @Published var account: SteamCloudAccount? = nil
    @Published private(set) var isAuthenticating: Bool = false
    @Published var lastError: String? = nil
    /// Set when a cloud op fails because Steam rejected our token. The UI shows
    /// a "Reconnect" prompt; cleared on a successful re-sign-in.
    @Published var sessionExpired: Bool = false

    private let client = CloudSyncClient()

    /// Keychain account key under which the encoded `SteamCloudAccount` lives.
    private static let keychainAccount = "steam-cloud-auth"

    func load() {
        // Preferred: the Keychain under the current (BEER) service.
        if let data = Keychain.get(account: Self.keychainAccount),
           let payload = try? JSONDecoder.gamenative.decode(SteamCloudAccount.self, from: data) {
            account = payload
            return
        }
        // Legacy 1: a Keychain item under the old "GameNativeMac" service —
        // re-store it under the new service and drop the old entry.
        if let data = Keychain.get(account: Self.keychainAccount, service: Keychain.legacyService),
           let payload = try? JSONDecoder.gamenative.decode(SteamCloudAccount.self, from: data) {
            account = payload
            persist()
            Keychain.delete(account: Self.keychainAccount, service: Keychain.legacyService)
            return
        }
        // Legacy 2: a plaintext steam-cloud-auth.json from even older builds —
        // migrate it into the Keychain, then delete the cleartext copy.
        if let data = try? Data(contentsOf: AppPaths.steamCloudAuthStateURL),
           let payload = try? JSONDecoder.gamenative.decode(SteamCloudAccount.self, from: data) {
            account = payload
            persist()
            try? FileManager.default.removeItem(at: AppPaths.steamCloudAuthStateURL)
        }
    }

    func signOut() {
        account = nil
        sessionExpired = false
        Keychain.delete(account: Self.keychainAccount)
        // Remove any leftover legacy plaintext file too.
        try? FileManager.default.removeItem(at: AppPaths.steamCloudAuthStateURL)
    }

    /// Inspect an error thrown by a cloud operation; if it's an expired/revoked
    /// token, flip `sessionExpired` so the UI can prompt a reconnect.
    func noteCloudError(_ error: Error) {
        if case CloudSyncClientError.authExpired = error {
            sessionExpired = true
        }
    }

    private func persist() {
        guard let account, let data = try? JSONEncoder.gamenative.encode(account) else { return }
        do {
            // Deliberately no plaintext fallback: if the Keychain write fails,
            // the token stays in memory for this session and the user re-auths
            // next launch — we never put the credential back on disk in cleartext.
            try Keychain.set(data, account: Self.keychainAccount)
        } catch {
            lastError = (error as? Keychain.KeychainError)?.errorDescription
                ?? "Couldn't securely save your Steam sign-in."
        }
    }

    /// Run QR sign-in via the helper. `onQRReady` fires for every challenge URL
    /// (re-render the QR each time). On approval we persist account + token.
    func runQRAuth(onQRReady: @escaping @MainActor (QRSession) -> Void) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }

        let result: CloudSyncClient.AuthResult
        do {
            result = try await client.authenticate(onChallenge: { url in
                Task { @MainActor in onQRReady(QRSession(challengeURL: url)) }
            })
        } catch let err as CloudSyncClientError {
            throw SteamAuthError.helper(err.errorDescription ?? "Sign-in failed.")
        }

        account = SteamCloudAccount(
            accountName: result.account,
            steamID64: Self.extractSteamID(fromJWT: result.refreshToken) ?? "0",
            refreshToken: result.refreshToken,
            connectedAt: Date()
        )
        sessionExpired = false
        persist()
    }

    // MARK: - JWT parsing (for the SteamID64 sub claim only)

    private static func extractSteamID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["sub"] as? String
    }
}
