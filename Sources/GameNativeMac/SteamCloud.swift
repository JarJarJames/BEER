import CryptoKit
import Foundation

// Thin client over Steam's ICloudService Web API. Every call needs a fresh
// user access token, which we get from SteamAuthStore.getAccessToken().
//
// Endpoints we use (all hosted at api.steampowered.com):
//   GET  ICloudService/EnumerateUserFiles/v1   — list cloud files for app
//   GET  <returned url>                         — download a file
//   POST ICloudService/BeginHTTPUpload/v1       — start an upload, get URL
//   PUT  <returned url>                         — upload bytes
//   POST ICloudService/CommitHTTPUpload/v1      — finalize the upload

struct CloudFile: Equatable, Hashable {
    let appID: Int
    let filename: String      // Steam-Cloud-relative path, "/"-separated
    let size: Int
    let timestamp: Date       // Steam-side mtime
    let downloadURL: URL?     // pre-signed; no auth needed for the GET
    let sha1Hex: String?
}

struct CloudUploadHandle {
    let appID: Int
    let filename: String
    let sha1Hex: String
    let uploadURL: URL
    let headers: [(name: String, value: String)]
}

enum SteamCloudError: LocalizedError {
    case http(Int, String)
    case invalidResponse(String)
    case missingDownloadURL(String)
    case missingUploadURL(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "Steam Cloud returned HTTP \(code): \(body.prefix(200))"
        case .invalidResponse(let detail):
            return "Steam Cloud returned an unexpected response: \(detail.prefix(300))"
        case .missingDownloadURL(let name):
            return "Steam didn't return a download URL for \(name)."
        case .missingUploadURL(let name):
            return "Steam didn't return an upload URL for \(name)."
        }
    }
}

struct SteamCloud {
    private let session = URLSession.shared

    // MARK: - Enumerate

    /// List every cloud file the user has for this app.
    func enumerateUserFiles(appID: Int, accessToken: String) async throws -> [CloudFile] {
        var comp = URLComponents(string: "https://api.steampowered.com/ICloudService/EnumerateUserFiles/v1/")!
        comp.queryItems = [
            URLQueryItem(name: "access_token", value: accessToken),
            URLQueryItem(name: "appid", value: String(appID)),
            URLQueryItem(name: "extended_details", value: "1"),
            URLQueryItem(name: "count", value: "1000")
        ]

        let (data, response) = try await session.data(from: comp.url!)
        try checkHTTP(response, body: data)

        struct Envelope: Decodable { let response: Inner }
        struct Inner: Decodable { let files: [RawFile]?; let total_files: Int? }
        struct RawFile: Decodable {
            let appid: Int
            let filename: String
            let timestamp: UInt64
            let file_size: Int
            let url: String?
            let file_sha: String?
        }

        let env = try JSONDecoder().decode(Envelope.self, from: data)
        return (env.response.files ?? []).map { raw in
            CloudFile(
                appID: raw.appid,
                filename: raw.filename,
                size: raw.file_size,
                timestamp: Date(timeIntervalSince1970: TimeInterval(raw.timestamp)),
                downloadURL: raw.url.flatMap(URL.init(string:)),
                sha1Hex: raw.file_sha
            )
        }
    }

    // MARK: - Download

    /// Download a single cloud file's bytes via its pre-signed URL.
    func download(file: CloudFile) async throws -> Data {
        guard let url = file.downloadURL else {
            throw SteamCloudError.missingDownloadURL(file.filename)
        }
        let (data, response) = try await session.data(from: url)
        try checkHTTP(response, body: data)
        return data
    }

    // MARK: - Upload (3-step: begin → PUT → commit)

    func beginUpload(
        appID: Int,
        filename: String,
        data: Data,
        accessToken: String
    ) async throws -> CloudUploadHandle {
        let sha = sha1Hex(data)
        let payload: [String: Any] = [
            "appid": appID,
            "file_size": data.count,
            "filename": filename,
            "file_sha": sha,
            "is_public": false,
            "platforms_to_sync": ["all"]
        ]

        let respData = try await postFormJSON(
            to: "https://api.steampowered.com/ICloudService/BeginHTTPUpload/v1/",
            input: payload,
            accessToken: accessToken
        )

        struct Envelope: Decodable { let response: Inner }
        struct Inner: Decodable {
            let ugcid: String?
            let timestamp: UInt64?
            let url_host: String?
            let url_path: String?
            let use_https: Bool?
            let request_headers: [HeaderPair]?
        }
        struct HeaderPair: Decodable { let name: String; let value: String }

        let env = try JSONDecoder().decode(Envelope.self, from: respData)
        let scheme = (env.response.use_https ?? true) ? "https" : "http"
        guard let host = env.response.url_host,
              let path = env.response.url_path,
              let url = URL(string: "\(scheme)://\(host)\(path)") else {
            throw SteamCloudError.missingUploadURL(filename)
        }
        return CloudUploadHandle(
            appID: appID,
            filename: filename,
            sha1Hex: sha,
            uploadURL: url,
            headers: (env.response.request_headers ?? []).map { ($0.name, $0.value) }
        )
    }

    func putBytes(_ data: Data, to handle: CloudUploadHandle) async throws {
        var req = URLRequest(url: handle.uploadURL)
        req.httpMethod = "PUT"
        for (k, v) in handle.headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (body, response) = try await session.upload(for: req, from: data)
        try checkHTTP(response, body: body)
    }

    func commitUpload(_ handle: CloudUploadHandle, succeeded: Bool, accessToken: String) async throws {
        let payload: [String: Any] = [
            "transfer_succeeded": succeeded,
            "appid": handle.appID,
            "file_sha": handle.sha1Hex,
            "filename": handle.filename
        ]
        let data = try await postFormJSON(
            to: "https://api.steampowered.com/ICloudService/CommitHTTPUpload/v1/",
            input: payload,
            accessToken: accessToken
        )
        // Response body unused — non-2xx already throws via checkHTTP.
        _ = data
    }

    // MARK: - Helpers

    private func postFormJSON(to urlString: String, input: [String: Any], accessToken: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw SteamCloudError.invalidResponse("bad URL")
        }
        let jsonData = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let encoded = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jsonString
        let accessEnc = accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? accessToken
        let body = "input_json=\(encoded)&access_token=\(accessEnc)&format=json"

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: req)
        try checkHTTP(response, body: data)
        return data
    }

    private func checkHTTP(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SteamCloudError.invalidResponse("no HTTP response")
        }
        guard 200..<300 ~= http.statusCode else {
            throw SteamCloudError.http(http.statusCode, String(data: body, encoding: .utf8) ?? "")
        }
    }

    private func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
