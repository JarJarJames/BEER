import Foundation

func scrub(_ line: String) -> String {
    var out = line.replacingOccurrences(of: "\r", with: "")
    if let re = try? NSRegularExpression(pattern: "\\u{1B}\\[[0-9;]*[a-zA-Z]") {
        let range = NSRange(out.startIndex..., in: out)
        out = re.stringByReplacingMatches(in: out, range: range, withTemplate: "")
    }
    return out
}

func parseStatusPhrase(_ line: String) -> String? {
    let lower = line.lowercased()
    if lower.contains("got app info") || lower.contains("got app info!") { return "Got app info" }
    if lower.contains("got cdn auth token") { return "Authenticated with CDN" }
    if lower.contains("pre-allocating") { return "Pre-allocating disk space…" }
    if lower.contains("validating") { return "Validating files…" }
    if lower.contains("downloading depot") { return "Downloading…" }
    return nil
}

func parseProgressFraction(_ line: String) -> Double? {
    // DepotDownloader prints lines like " 12.34% C:\\... " during download.
    if let m = line.firstMatch(of: /^\s*([0-9]+(?:\.[0-9]+)?)%/) {
        if let v = Double(m.output.1) { return max(0, min(1, v / 100)) }
    }
    // Older builds: "Downloaded XYZ / TOTAL MB"
    if let m = line.firstMatch(of: /Downloaded ([0-9.]+)\s*\/\s*([0-9.]+)\s*MB/) {
        if let d = Double(m.output.1), let t = Double(m.output.2), t > 0 {
            return max(0, min(1, d / t))
        }
    }
    return nil
}

func parseAuthFailure(_ line: String) -> String? {
    let lower = line.lowercased()
    if lower.contains("invalid password") { return "Invalid password" }
    if lower.contains("rate limit") { return "Steam is rate-limiting sign-in attempts. Wait a few minutes." }
    if lower.contains("unable to logon") {
        return String(line.trimmingCharacters(in: .whitespaces))
    }
    if lower.contains("guard data was rejected") { return "Steam Guard data was rejected" }
    return nil
}

/// DepotDownloader: "App 3368600 (Brushes with Death) is not available from
/// this account." Returns the human-readable part for the error message.
func parseNotOwned(_ line: String) -> String? {
    guard line.contains("is not available from this account") else { return nil }
    if let m = line.firstMatch(of: /App ([0-9]+) \(([^)]*)\) is not available/) {
        let name = String(m.output.2).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "App \(m.output.1)" : name
    }
    return "This content"
}
