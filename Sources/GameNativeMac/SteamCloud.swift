import Foundation

// Steam Cloud read access via the user-web path.
//
// Why this isn't ICloudService: that Web API is locked behind a publisher
// key, which third parties don't have access to. Even with a valid user
// access_token from QR auth, EnumerateUserFiles returns 401 with
// "Please verify your key= parameter." (Verified against a live account.)
//
// What does work: the same web pages Steam shows the user when they manage
// their cloud saves in a browser. After we hand a steamLoginSecure cookie
// to store.steampowered.com (via SteamAuthStore.ensureWebSession), GET
// /account/remotestorageapp/?appid=<id> renders one HTML row per cloud
// file with the folder name, relative path, size, mtime, and a pre-signed
// cdn.steamusercontent.com download URL.
//
// LIMIT: this path is read-only. Steam's web UI exposes View / Download /
// Delete, but no upload form. Push-to-cloud from a third-party app without
// a publisher key or a running real Steam.exe is not feasible — that's a
// Valve design choice. CloudSyncEngine.push() throws .uploadNotSupported
// to surface that clearly in the UI.

struct CloudFile: Equatable, Hashable {
    /// The Steam "folder" tag for this file. Each folder maps to a stable
    /// Windows location (e.g. WinSavedGames → %USERPROFILE%\Saved Games\).
    let folder: String
    /// Path under that folder, "/"-separated, with case as Steam stores it.
    let relativePath: String
    let size: Int
    let timestamp: Date
    let downloadURL: URL

    var displayPath: String { "\(folder)/\(relativePath)" }
}

enum SteamCloudError: LocalizedError {
    case http(Int, String)
    case invalidResponse(String)
    case sessionExpired
    case uploadNotSupported

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "Steam returned HTTP \(code): \(body.prefix(200))"
        case .invalidResponse(let detail):
            return "Steam returned an unexpected response: \(detail.prefix(300))"
        case .sessionExpired:
            return "Steam web session expired — please reconnect Cloud."
        case .uploadNotSupported:
            return "Push to Steam Cloud isn't supported: Valve gates the upload API behind a Publisher Web API Key that third-party apps can't obtain. Saves can be pulled down from cloud but the reverse needs a real Steam client running."
        }
    }
}

struct SteamCloud {
    private let session = URLSession.shared

    /// List all cloud files for an app. Requires SteamAuthStore.ensureWebSession()
    /// to have been called first so URLSession.shared has the right cookies.
    func enumerateUserFiles(appID: Int) async throws -> [CloudFile] {
        guard let url = URL(string: "https://store.steampowered.com/account/remotestorageapp/?appid=\(appID)") else {
            throw SteamCloudError.invalidResponse("bad URL")
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw SteamCloudError.invalidResponse("no HTTP response")
        }
        guard 200..<300 ~= http.statusCode else {
            throw SteamCloudError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw SteamCloudError.invalidResponse("response wasn't UTF-8")
        }

        // If we got redirected to the login page, the session expired.
        if html.contains("https://store.steampowered.com/login/") &&
           !html.contains("remotestorageapp") {
            throw SteamCloudError.sessionExpired
        }

        return Self.parseFileRows(in: html)
    }

    /// Download a single file's bytes via its pre-signed cdn URL.
    /// No additional auth needed — Steam embeds the token in the URL.
    func download(file: CloudFile) async throws -> Data {
        let (data, response) = try await session.data(from: file.downloadURL)
        guard let http = response as? HTTPURLResponse else {
            throw SteamCloudError.invalidResponse("no HTTP response")
        }
        guard 200..<300 ~= http.statusCode else {
            throw SteamCloudError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - HTML parsing

    /// Extracts each `<tr>` row of the file table. The page's structure is
    /// stable (it's been the same for ~10 years), but we keep the regex
    /// lenient on whitespace and only require the five columns we need.
    static func parseFileRows(in html: String) -> [CloudFile] {
        // (?s) = DOTALL so `.` spans newlines.
        // Captures (1)=folder, (2)=relative path, (3)=human size, (4)=human date, (5)=download URL.
        let pattern = #"(?s)<tr>\s*<td>\s*([A-Za-z][A-Za-z0-9_]*)\s*</td>\s*<td>\s*([^<]+?)\s*</td>\s*<td>\s*([\d.]+\s*[A-Za-z]+)\s*</td>\s*<td>\s*([^<]+?)\s*</td>\s*<td>\s*<a\s+href="([^"]+)"[^>]*>\s*Download\s*</a>"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(html.startIndex..., in: html)
        var out: [CloudFile] = []

        regex.enumerateMatches(in: html, range: nsRange) { match, _, _ in
            guard let m = match, m.numberOfRanges == 6 else { return }
            func g(_ idx: Int) -> String {
                Range(m.range(at: idx), in: html).map { String(html[$0]) } ?? ""
            }
            let folder = g(1).trimmingCharacters(in: .whitespacesAndNewlines)
            let path = g(2).trimmingCharacters(in: .whitespacesAndNewlines)
            let sizeStr = g(3).trimmingCharacters(in: .whitespacesAndNewlines)
            let dateStr = g(4).trimmingCharacters(in: .whitespacesAndNewlines)
            let urlStr = g(5).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: urlStr) else { return }
            out.append(CloudFile(
                folder: folder,
                relativePath: path,
                size: parseHumanSize(sizeStr),
                timestamp: parseHumanDate(dateStr) ?? .distantPast,
                downloadURL: url
            ))
        }
        return out
    }

    static func parseHumanSize(_ s: String) -> Int {
        let parts = s.split(whereSeparator: { $0 == " " || $0 == "\u{a0}" })
        guard parts.count >= 2,
              let num = Double(parts[0]) else { return 0 }
        let unit = parts[1].lowercased()
        let mult: Double
        switch unit {
        case "b": mult = 1
        case "kb": mult = 1024
        case "mb": mult = 1024 * 1024
        case "gb": mult = 1024 * 1024 * 1024
        default: mult = 1
        }
        return Int(num * mult)
    }

    /// Steam's web shows dates like "Apr 26 @ 6:39pm" (current year implied)
    /// or "Apr 26, 2023 @ 6:39pm" for older entries. We parse both, default
    /// to current year, and fall back a year if that would put the date in
    /// the future.
    static func parseHumanDate(_ s: String) -> Date? {
        let formats = ["MMM d, yyyy @ h:mma", "MMM d @ h:mma"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for f in formats {
            formatter.dateFormat = f
            if let parsed = formatter.date(from: s) {
                guard !s.contains(",") else { return parsed }
                // No year in the source string — assume current; rewind a
                // year if that lands in the future.
                let cal = Calendar(identifier: .gregorian)
                var comps = cal.dateComponents(in: .current, from: parsed)
                comps.year = cal.component(.year, from: Date())
                guard var d = cal.date(from: comps) else { return parsed }
                if d > Date() {
                    comps.year! -= 1
                    d = cal.date(from: comps) ?? d
                }
                return d
            }
        }
        return nil
    }
}
