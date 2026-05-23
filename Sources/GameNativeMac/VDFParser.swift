import Foundation

// Minimal Valve KeyValues (VDF) parser. We use it to read the output of
// `steamcmd +app_info_print <appid>`, which is the canonical source of a
// Steam game's launch executable + arguments. Format is nested
// "key" "value" / "key" { ... } blocks; we only need enough to extract:
//
//   <appid>.config.launch.<n>.executable   (Windows entry preferred)
//   <appid>.config.launch.<n>.arguments
//   <appid>.config.installdir
//   <appid>.common.name
indirect enum VDFValue {
    case string(String)
    case object([(String, VDFValue)])   // preserves insertion order — launch keys are "0","1","2"...

    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    func child(_ key: String) -> VDFValue? {
        guard case .object(let entries) = self else { return nil }
        return entries.first(where: { $0.0.caseInsensitiveCompare(key) == .orderedSame })?.1
    }

    var orderedEntries: [(String, VDFValue)] {
        if case .object(let entries) = self { return entries }
        return []
    }
}

enum VDFParser {
    /// Parse a complete VDF document. The output of `app_info_print` has some
    /// header lines before the keyvalues block, so we scan forward to the
    /// first `"` and start there.
    static func parse(_ source: String) -> VDFValue? {
        let scalars = Array(source.unicodeScalars)
        guard let start = scalars.firstIndex(where: { $0 == "\"" }) else { return nil }
        var idx = start
        guard let rootKey = readString(scalars, &idx) else { return nil }
        _ = rootKey
        skipWhitespaceAndComments(scalars, &idx)
        guard idx < scalars.count, scalars[idx] == "{" else { return nil }
        return parseObject(scalars, &idx)
    }

    /// Convenience: pull the launch info out of an app_info_print blob for a
    /// known appID. Prefers entries with `config.oslist` containing "windows";
    /// otherwise returns the first entry that has an executable.
    static func extractLaunch(fromAppInfo source: String, appID: Int) -> (executable: String, arguments: String?, installDir: String?, name: String?)? {
        guard let parsed = parse(source) else { return nil }

        // Top-level may be the appID block already, or wrap it.
        let appBlock: VDFValue
        if let direct = parsed.child(String(appID)) {
            appBlock = direct
        } else {
            appBlock = parsed
        }

        let config = appBlock.child("config")
        let launch = config?.child("launch")
        let installDir = config?.child("installdir")?.asString
        let name = appBlock.child("common")?.child("name")?.asString

        guard let launch else { return nil }

        // Look for the first Windows launch entry, ordered by numeric key.
        let sorted = launch.orderedEntries.sorted { lhs, rhs in
            let li = Int(lhs.0) ?? Int.max
            let ri = Int(rhs.0) ?? Int.max
            return li < ri
        }

        var fallback: (String, String?)?
        for (_, entry) in sorted {
            guard let exe = entry.child("executable")?.asString, !exe.isEmpty else { continue }
            let args = entry.child("arguments")?.asString
            let oslist = entry.child("config")?.child("oslist")?.asString ?? ""
            if oslist.localizedCaseInsensitiveContains("windows") {
                return (exe, args, installDir, name)
            }
            if fallback == nil {
                fallback = (exe, args)
            }
        }
        if let (exe, args) = fallback {
            return (exe, args, installDir, name)
        }
        return nil
    }

    // MARK: - Internals

    private static func skipWhitespaceAndComments(_ s: [Unicode.Scalar], _ i: inout Int) {
        while i < s.count {
            let c = s[i]
            if Character(c).isWhitespace {
                i += 1
            } else if c == "/" && i + 1 < s.count && s[i + 1] == "/" {
                while i < s.count && s[i] != "\n" { i += 1 }
            } else {
                break
            }
        }
    }

    private static func readString(_ s: [Unicode.Scalar], _ i: inout Int) -> String? {
        skipWhitespaceAndComments(s, &i)
        guard i < s.count else { return nil }
        if s[i] == "\"" {
            i += 1
            var out = ""
            while i < s.count {
                let c = s[i]
                if c == "\\" && i + 1 < s.count {
                    let next = s[i + 1]
                    switch next {
                    case "n": out.unicodeScalars.append("\n")
                    case "t": out.unicodeScalars.append("\t")
                    case "\"": out.unicodeScalars.append("\"")
                    case "\\": out.unicodeScalars.append("\\")
                    default: out.unicodeScalars.append(next)
                    }
                    i += 2
                } else if c == "\"" {
                    i += 1
                    return out
                } else {
                    out.unicodeScalars.append(c)
                    i += 1
                }
            }
            return out
        } else {
            // Bareword (rare in VDF, but tolerate)
            var out = ""
            while i < s.count, !Character(s[i]).isWhitespace, s[i] != "{", s[i] != "}" {
                out.unicodeScalars.append(s[i])
                i += 1
            }
            return out.isEmpty ? nil : out
        }
    }

    private static func parseObject(_ s: [Unicode.Scalar], _ i: inout Int) -> VDFValue? {
        guard i < s.count, s[i] == "{" else { return nil }
        i += 1
        var entries: [(String, VDFValue)] = []

        while true {
            skipWhitespaceAndComments(s, &i)
            guard i < s.count else { break }
            if s[i] == "}" {
                i += 1
                return .object(entries)
            }
            guard let key = readString(s, &i) else { break }
            skipWhitespaceAndComments(s, &i)
            guard i < s.count else { break }
            if s[i] == "{" {
                guard let val = parseObject(s, &i) else { break }
                entries.append((key, val))
            } else if let valueStr = readString(s, &i) {
                entries.append((key, .string(valueStr)))
            } else {
                break
            }
        }

        return .object(entries)
    }
}
