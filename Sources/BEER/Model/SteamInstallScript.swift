import Foundation

/// One `installscript.vdf`: what Steam runs on a game's first launch. Each
/// redistributable depot (VC++, DirectX, .NET, PhysX, …) ships one beside its
/// installer, so a game's `_CommonRedist` folder already says exactly which
/// runtimes it needs and how to install them silently. Only the `Run Process`
/// section is read; `Registry` entries are not applied.
struct SteamInstallScript: Equatable {
    struct RunProcess: Equatable {
        /// The entry's name, e.g. `x64` or `dxsetup`.
        let name: String
        /// The registry key Steam records the run under, so it never runs
        /// twice. BEER keeps its own receipt instead (see `SteamRedist`), but
        /// keys it the same way.
        let hasRunKey: String?
        let commands: [Command]
    }

    struct Command: Equatable {
        let executable: String
        let arguments: [String]
    }

    let runProcesses: [RunProcess]

    /// `installDirectory` is the Windows path `%INSTALLDIR%` stands for.
    init(parsing text: String, installDirectory: String) {
        let root = KeyValues.parse(text)["installscript"]
        let expand = { (value: String) in
            value.replacingOccurrences(of: "%INSTALLDIR%", with: installDirectory, options: .caseInsensitive)
        }

        runProcesses = (root?["run process"]?.children ?? []).compactMap { entry in
            let process = entry.value
            // Bottles are always 64-bit Windows, so only entries that insist
            // on 32-bit Windows are skipped.
            guard process["requirement_os"]?["is64bitwindows"]?.string != "0" else { return nil }

            // `process 1`/`command 1`, `process 2`/`command 2`, … run in order.
            var commands: [Command] = []
            while let executable = process["process \(commands.count + 1)"]?.string {
                let arguments = process["command \(commands.count + 1)"]?.string ?? ""
                commands.append(Command(executable: expand(executable), arguments: Self.split(expand(arguments))))
            }
            guard !commands.isEmpty else { return nil }
            return RunProcess(name: entry.key, hasRunKey: process["hasrunkey"]?.string, commands: commands)
        }
    }

    /// A Windows command line split into arguments, keeping quoted runs
    /// (paths with spaces) together and dropping the quotes.
    static func split(_ commandLine: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quoted = false
        for character in commandLine {
            switch character {
            case "\"": quoted.toggle()
            case " " where !quoted:
                if !current.isEmpty { arguments.append(current) }
                current = ""
            default: current.append(character)
            }
        }
        if !current.isEmpty { arguments.append(current) }
        return arguments
    }
}
