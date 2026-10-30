import Foundation

/// Works out which `WindowsDependency`s a Wine prefix already has, without
/// running Wine. Three sources, any of which counts:
///   • BEER's own receipt, written after an install succeeds;
///   • `winetricks.log`, for bottles someone already ran winetricks on;
///   • the DLLs themselves — a real Microsoft DLL where Wine would otherwise
///     have its builtin placeholder (e.g. a game installer that ran vc_redist).
enum WindowsDependencyDetector {
    /// Wine stamps this at offset 0x40 (the DOS stub) of every builtin DLL it
    /// copies into system32/syswow64. Microsoft's DLLs have their own stub there.
    static let wineBuiltinMarker = Data("Wine builtin DLL".utf8)
    static let winePlaceholderMarker = Data("Wine placeholder DLL".utf8)
    private static let markerOffset = 0x40

    static let receiptFileName = "beer-dependencies.log"
    static let winetricksLogFileName = "winetricks.log"

    static func installed(inPrefix prefix: URL) -> Set<WindowsDependency> {
        let receipt = (try? String(contentsOf: prefix.appendingPathComponent(receiptFileName), encoding: .utf8)) ?? ""
        let winetricks = (try? String(contentsOf: prefix.appendingPathComponent(winetricksLogFileName), encoding: .utf8)) ?? ""

        var found = parseReceipt(receipt).union(parseWinetricksLog(winetricks))
        for dependency in WindowsDependency.allCases where hasNativeDLLs(for: dependency, inPrefix: prefix) {
            found.insert(dependency)
        }
        return found
    }

    /// One dependency raw value per line; unknown lines are ignored so an older
    /// BEER reading a newer receipt doesn't choke.
    static func parseReceipt(_ text: String) -> Set<WindowsDependency> {
        Set(lines(of: text).compactMap(WindowsDependency.init(rawValue:)))
    }

    static func parseWinetricksLog(_ text: String) -> Set<WindowsDependency> {
        let verbs = Set(lines(of: text).map { $0.lowercased() })
        return Set(WindowsDependency.allCases.filter { !$0.winetricksVerbs.isDisjoint(with: verbs) })
    }

    /// The receipt text after recording `dependency`, keeping what was there.
    static func receipt(byAdding dependency: WindowsDependency, to existing: String) -> String {
        var entries = lines(of: existing)
        if !entries.contains(dependency.rawValue) { entries.append(dependency.rawValue) }
        return entries.joined(separator: "\n") + "\n"
    }

    /// True when the file at `url` is Wine's own builtin/placeholder copy.
    static func isWineBuiltin(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(markerOffset))) != nil,
              let stub = try? handle.read(upToCount: winePlaceholderMarker.count) else { return false }
        return stub.starts(with: wineBuiltinMarker) || stub.starts(with: winePlaceholderMarker)
    }

    /// A DLL that exists and isn't Wine's — i.e. something a real installer put there.
    static func isNativeDLL(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) && !isWineBuiltin(url)
    }

    static func hasNativeDLLs(for dependency: WindowsDependency, inPrefix prefix: URL) -> Bool {
        let probes = nativeProbeDLLs(for: dependency)
        return !probes.isEmpty && probes.allSatisfy { isNativeDLL(prefix.appendingPathComponent($0)) }
    }

    /// Files that only a real install of the dependency leaves non-Wine.
    /// Both architectures for VC++, since a game may need either.
    static func nativeProbeDLLs(for dependency: WindowsDependency) -> [String] {
        switch dependency {
        case .vcRedist:
            ["drive_c/windows/syswow64/vcruntime140.dll", "drive_c/windows/system32/vcruntime140.dll"]
        case .directX:
            ["drive_c/windows/syswow64/d3dx9_43.dll"]
        }
    }

    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
