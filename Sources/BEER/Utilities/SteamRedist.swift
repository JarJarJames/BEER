import Foundation

/// Finding and bookkeeping for the redistributable install scripts Steam
/// downloads with a game. `BottleStore.installSteamRedistributables` runs them.
enum SteamRedist {
    static let folderName = "_CommonRedist"
    static let scriptFileName = "installscript.vdf"
    static let receiptFileName = "beer-steam-redist.log"

    /// Exit codes Microsoft's redist installers use for "done": success,
    /// already installed (1638), reboot needed (3010), and a newer VC++ 14
    /// already present (5100).
    static let successExitCodes: Set<Int32> = [0, 1638, 3010, 5100]

    /// Install-script paths, relative to the game folder, in a stable order.
    static func installScripts(in installDirectory: URL) -> [String] {
        let root = installDirectory.appendingPathComponent(folderName, isDirectory: true)
        // No `_CommonRedist` is the normal case for most games.
        guard let paths = try? FileManager.default.subpathsOfDirectory(atPath: root.path) else { return [] }
        return paths
            .filter { ($0 as NSString).lastPathComponent.caseInsensitiveCompare(scriptFileName) == .orderedSame }
            .map { folderName + "/" + $0 }
            .sorted()
    }

    /// Microsoft's .NET Framework installers don't complete under Wine — they
    /// hang the launch instead — so those depots are left alone.
    static func isSkipped(_ scriptPath: String) -> Bool {
        scriptPath.lowercased().hasPrefix(folderName.lowercased() + "/dotnet/")
    }

    /// The VC++ year a script installs, from Steam's `vcredist/<year>/` layout.
    static func vcRedistYear(ofScript scriptPath: String) -> String? {
        let folders = scriptPath.split(separator: "/").dropLast()
        guard folders.count >= 2, folders[folders.count - 2].lowercased() == "vcredist" else { return nil }
        return String(folders[folders.count - 1])
    }

    /// What a finished entry is recorded as: its `hasrunkey` and name, like
    /// Steam, or its script's path when it has no key.
    static func receiptID(for process: SteamInstallScript.RunProcess, scriptPath: String) -> String {
        "\(process.hasRunKey ?? scriptPath)\\\(process.name)".lowercased()
    }

    static func parseReceipt(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func receipt(_ ids: Set<String>) -> String {
        ids.sorted().joined(separator: "\n") + "\n"
    }

    /// The Windows path Wine gives a Mac path through its `Z:` drive, which
    /// every bottle maps to `/`.
    static func windowsPath(_ url: URL) -> String {
        "Z:" + url.path.replacingOccurrences(of: "/", with: "\\")
    }
}
