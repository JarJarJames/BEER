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

/// The status line through a DepotDownloader run. Each depot pre-allocates
/// (or, for files already there, validates) every file first, one line per
/// file, then prints only a percentage per chunk while it downloads. Going by
/// the phrases alone, the status stayed on the last file's "Pre-allocating"
/// or "Validating" for the whole download.
struct DepotDownloaderStatus {
    private(set) var current: String?

    /// The new status after `line`, or nil when it doesn't change.
    mutating func update(with line: String) -> String? {
        let next = parseProgressFraction(line) != nil ? "Downloading…" : parseStatusPhrase(line)
        guard let next, next != current else { return nil }
        current = next
        return next
    }
}

/// One progress fraction for a whole DepotDownloader run, 0 to 1, that never
/// goes backwards. DepotDownloader's percentage lines are for the depot it is
/// on, and it downloads depots one after another, so passed straight through
/// they filled the bar once per depot.
///
/// It names every depot with "Processing depot <id>" before downloading any,
/// then prints "Downloading depot <id>" as each one starts and "Depot <id> -
/// Downloaded …" as it ends. Each depot's share of the bar is its size in
/// `depotBytes`; one with no size there counts as the average of those that
/// have one, and with no sizes at all every depot gets the same share.
struct DepotDownloadProgress {
    private let depotBytes: [Int: Int64]
    private var depots: [Int] = []
    private var finished: Set<Int> = []
    private var current: Int?
    private var currentFraction = 0.0
    private var complete = false
    private(set) var fraction = 0.0

    init(depotBytes: [Int: Int64] = [:]) {
        self.depotBytes = depotBytes
    }

    /// The overall fraction after `line`, or nil when it hasn't moved forward.
    mutating func update(with line: String) -> Double? {
        if let id = depotID(in: line, matching: /^\s*Processing depot ([0-9]+)\s*$/) {
            add(id)
        } else if let id = depotID(in: line, matching: /^\s*Downloading depot ([0-9]+)\s*$/) {
            // Not "Downloading depot <id> manifest", which comes while processing.
            if let current { finished.insert(current) }
            add(id)
            current = id
            currentFraction = 0
        } else if let id = depotID(in: line, matching: /^\s*Depot ([0-9]+) - Downloaded\s/) {
            // A depot whose files a later depot overwrites never reaches 100%.
            add(id)
            finished.insert(id)
        } else if line.contains("Total downloaded:") {
            complete = true
        } else if let depotFraction = parseProgressFraction(line) {
            currentFraction = max(currentFraction, depotFraction)
        } else {
            return nil
        }
        let overall = overall
        guard overall > fraction else { return nil }
        fraction = overall
        return overall
    }

    private var overall: Double {
        if complete { return 1 }
        // Output without depot lines: the one percentage is all there is.
        guard !depots.isEmpty else { return currentFraction }
        let known = depots.compactMap { depotBytes[$0] }.filter { $0 > 0 }
        let unknownShare = known.isEmpty ? 1 : Double(known.reduce(0, +)) / Double(known.count)
        func share(_ id: Int) -> Double {
            depotBytes[id].flatMap { $0 > 0 ? Double($0) : nil } ?? unknownShare
        }
        let total = depots.map(share).reduce(0, +)
        var done = depots.filter(finished.contains).map(share).reduce(0, +)
        if let current, !finished.contains(current) {
            done += share(current) * currentFraction
        }
        return min(1, done / total)
    }

    private mutating func add(_ id: Int) {
        if !depots.contains(id) { depots.append(id) }
    }

    private func depotID(in line: String, matching pattern: Regex<(Substring, Substring)>) -> Int? {
        line.firstMatch(of: pattern).flatMap { Int($0.output.1) }
    }
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
///
/// Only the app-level line is fatal. "Depot 468550 is not available from this
/// account." is printed for optional depots (DLC, other platforms) while the
/// rest of the download proceeds, so it must not be reported as not owned.
func parseNotOwned(_ line: String) -> String? {
    guard let m = line.firstMatch(of: /App ([0-9]+) \(([^)]*)\) is not available from this account/) else {
        return nil
    }
    let name = String(m.output.2).trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? "App \(m.output.1)" : name
}
