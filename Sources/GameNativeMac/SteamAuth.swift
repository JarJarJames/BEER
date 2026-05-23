import Foundation

// Steam authentication via the IAuthenticationService QR flow, in pure Swift.
//
// The Steam Web API endpoints we hit:
//   BeginAuthSessionViaQR/v1       — start a QR session, returns challenge URL
//   PollAuthSessionStatus/v1       — poll for user approval, returns tokens
//   GenerateAccessTokenForApp/v1   — mint a fresh access token from a refresh
//
// The endpoints accept JSON via the `input_json=` URL-encoded form param and
// return JSON wrapped in {"response": {...}}. No protobuf libs needed.
//
// The refresh token we obtain has audience including "client", which is
// what ICloudService accepts. We identify as platform_type=2 (SteamClient)
// so the resulting token has full cloud privileges.
//
// Why this is separate from DepotDownloader's auth: DepotDownloader caches
// its own refresh token inside its .NET `account.config` blob (protobuf +
// DeflateStream); decoding that to share with us is more work than just
// having the user scan a second QR. Two scans the first time, persistent
// tokens forever after.

struct SteamCloudAccount: Codable, Equatable {
    var accountName: String
    var steamID64: String
    var refreshToken: String
    var cachedAccessToken: String?
    var accessTokenExpiresAt: Date?
    var connectedAt: Date
}

enum SteamAuthError: LocalizedError {
    case http(Int, String)
    case invalidResponse(String)
    case notSignedIn
    case timeout
    case canceled

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "Steam returned HTTP \(code): \(body.prefix(200))"
        case .invalidResponse(let detail):
            return "Steam returned an unexpected response: \(detail.prefix(300))"
        case .notSignedIn:
            return "Not signed in to Steam Cloud yet — click Connect first."
        case .timeout:
            return "Steam didn't see the QR scan within 3 minutes."
        case .canceled:
            return "Sign-in canceled."
        }
    }
}

@MainActor
final class SteamAuthStore: ObservableObject {
    @Published var account: SteamCloudAccount? = nil
    @Published private(set) var isAuthenticating: Bool = false
    @Published var lastError: String? = nil

    private let session = URLSession.shared

    func load() {
        guard let data = try? Data(contentsOf: AppPaths.steamCloudAuthStateURL),
              let payload = try? JSONDecoder.gamenative.decode(SteamCloudAccount.self, from: data) else {
            return
        }
        account = payload
    }

    func signOut() {
        account = nil
        try? FileManager.default.removeItem(at: AppPaths.steamCloudAuthStateURL)
    }

    private func persist() {
        guard let account else { return }
        if let data = try? JSONEncoder.gamenative.encode(account) {
            try? data.write(to: AppPaths.steamCloudAuthStateURL, options: .atomic)
        }
    }

    // MARK: - QR auth (3-step: begin → poll → persist)

    struct QRSession {
        let clientID: UInt64
        let requestID: String     // base64
        let challengeURL: String  // s.team/q/... — what goes into the QR
        let pollInterval: TimeInterval
    }

    /// Step 1: open a fresh QR session with Steam.
    func beginQRSession() async throws -> QRSession {
        let payload: [String: Any] = [
            "device_friendly_name": "GameNative for Mac",
            "platform_type": 2,            // EAuthTokenPlatformType.SteamClient
            "website_id": "Client",
            "device_details": [
                "device_friendly_name": "GameNative for Mac",
                "platform_type": 2
            ]
        ]
        let data = try await postJSON(
            to: "https://api.steampowered.com/IAuthenticationService/BeginAuthSessionViaQR/v1/",
            input: payload
        )

        struct Envelope: Decodable { let response: Inner }
        struct Inner: Decodable {
            let client_id: String?       // server returns as decimal string
            let request_id: String?      // base64
            let interval: Double?
            let challenge_url: String?
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        guard let cid = env.response.client_id.flatMap(UInt64.init),
              let rid = env.response.request_id,
              let url = env.response.challenge_url else {
            throw SteamAuthError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return QRSession(
            clientID: cid,
            requestID: rid,
            challengeURL: url,
            pollInterval: env.response.interval ?? 5
        )
    }

    /// Step 2: poll until either the user approves (Steam returns tokens) or
    /// we time out. Throws on cancellation via Task.cancel().
    func pollForCompletion(_ qr: QRSession) async throws -> SteamCloudAccount {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(qr.pollInterval))
            try Task.checkCancellation()

            let payload: [String: Any] = [
                "client_id": String(qr.clientID),
                "request_id": qr.requestID
            ]
            let data = try await postJSON(
                to: "https://api.steampowered.com/IAuthenticationService/PollAuthSessionStatus/v1/",
                input: payload
            )

            struct Envelope: Decodable { let response: Inner }
            struct Inner: Decodable {
                let refresh_token: String?
                let access_token: String?
                let account_name: String?
                let had_remote_interaction: Bool?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            if let refresh = env.response.refresh_token, !refresh.isEmpty,
               let access = env.response.access_token, !access.isEmpty,
               let name = env.response.account_name {
                return SteamCloudAccount(
                    accountName: name,
                    steamID64: extractSteamID(fromJWT: refresh) ?? "0",
                    refreshToken: refresh,
                    cachedAccessToken: access,
                    accessTokenExpiresAt: extractExpiration(fromJWT: access),
                    connectedAt: Date()
                )
            }
        }
        throw SteamAuthError.timeout
    }

    /// Convenience: run begin → poll → persist as a single async call.
    /// Caller provides a continuation closure that gets the QR session so
    /// the UI can display the QR while polling is in progress.
    func runQRAuth(onQRReady: @escaping @MainActor (QRSession) -> Void) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let qr = try await beginQRSession()
        onQRReady(qr)
        let result = try await pollForCompletion(qr)
        account = result
        persist()
    }

    // MARK: - Access token refresh

    /// Returns a non-expired access token, refreshing via Steam if needed.
    /// The cached access token has a ~1 hour lifetime; we treat anything
    /// within 60s of expiry as already expired and refresh proactively.
    func getAccessToken() async throws -> String {
        guard let account else { throw SteamAuthError.notSignedIn }
        if let cached = account.cachedAccessToken,
           let exp = account.accessTokenExpiresAt,
           exp > Date().addingTimeInterval(60) {
            return cached
        }
        let payload: [String: Any] = [
            "refresh_token": account.refreshToken,
            "steamid": account.steamID64,
            "renewal_type": 0
        ]
        let data = try await postJSON(
            to: "https://api.steampowered.com/IAuthenticationService/GenerateAccessTokenForApp/v1/",
            input: payload
        )

        struct Envelope: Decodable { let response: Inner }
        struct Inner: Decodable {
            let access_token: String?
            let refresh_token: String?
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        guard let newAccess = env.response.access_token, !newAccess.isEmpty else {
            throw SteamAuthError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }

        var updated = account
        updated.cachedAccessToken = newAccess
        updated.accessTokenExpiresAt = extractExpiration(fromJWT: newAccess)
        if let newRefresh = env.response.refresh_token, !newRefresh.isEmpty {
            updated.refreshToken = newRefresh
        }
        self.account = updated
        persist()
        return newAccess
    }

    // MARK: - HTTP helpers

    /// POST a JSON payload to a Steam Service endpoint using their
    /// `input_json=` form-encoded convention.
    private func postJSON(to urlString: String, input: [String: Any]) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw SteamAuthError.invalidResponse("bad URL")
        }
        let jsonData = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SteamAuthError.invalidResponse("could not encode payload")
        }
        let encoded = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jsonString
        let body = "input_json=\(encoded)&format=json".data(using: .utf8) ?? Data()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SteamAuthError.invalidResponse("no HTTP response")
        }
        guard 200..<300 ~= http.statusCode else {
            throw SteamAuthError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - JWT parsing (small enough to inline; we only need exp + sub)

    private func extractSteamID(fromJWT token: String) -> String? {
        decodeJWTPayload(token)?["sub"] as? String
    }

    private func extractExpiration(fromJWT token: String) -> Date? {
        guard let exp = decodeJWTPayload(token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - b64.count % 4) % 4
        b64 += String(repeating: "=", count: pad)
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

// Shared encoder/decoder so the persisted JSON matches our other stores'
// formatting and date conventions.
private extension JSONEncoder {
    static var gamenative: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
private extension JSONDecoder {
    static var gamenative: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
