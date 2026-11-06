import Foundation

/// How to start one game through the steamclient loader, and why it needs it.
/// `nil` from `make` means launch the exe directly, as most games are.
struct SteamClientLoaderPlan: Equatable {
    let is64Bit: Bool
    /// The exe is wrapped in SteamStub: inject gbe_fork's in-memory patch.
    let patchesSteamStub: Bool
    /// The game uses the pre-Steamworks `Steam.dll`: inject gbe_fork's stand-in.
    let injectsOldSteamLibrary: Bool
    /// Load GameOverlayRenderer into the game, for the few that look for it
    /// in their own memory rather than on disk.
    let injectsOverlay: Bool
    /// Keep the loader running until dismissed, for launchers that restart
    /// themselves and would otherwise come back to find no "Steam".
    let staysOpen: Bool

    static func make(
        executable: URL,
        installDir: URL,
        mode: SteamClientLoaderMode,
        injectsOverlay: Bool = false,
        staysOpen: Bool = false
    ) -> SteamClientLoaderPlan? {
        guard mode != .off, let header = PortableExecutable(contentsOf: executable) else { return nil }
        let wrapped = header.isSteamStubWrapped
        let oldLibrary = !header.is64Bit && hasOldSteamLibrary(beside: executable)
        let needsLoader = wrapped || oldLibrary || talksToSteamClientDirectly(executable, installDir: installDir)
        guard mode == .always || needsLoader else { return nil }
        return SteamClientLoaderPlan(
            is64Bit: header.is64Bit,
            patchesSteamStub: wrapped,
            injectsOldSteamLibrary: oldLibrary,
            injectsOverlay: injectsOverlay,
            staysOpen: staysOpen
        )
    }

    /// `Steam.dll` beside the exe: the Steam2-era library, 32-bit only.
    static func hasOldSteamLibrary(beside executable: URL) -> Bool {
        let folder = executable.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { $0.caseInsensitiveCompare("Steam.dll") == .orderedSame }
    }

    /// No `steam_api.dll` anywhere to patch, yet the exe names a SteamClient
    /// interface: it loads Steam's client library itself, which only the
    /// loader can stand in for. A DRM-free game names no such interface.
    static func talksToSteamClientDirectly(_ executable: URL, installDir: URL) -> Bool {
        guard !hasSteamAPI(in: installDir),
              let exe = try? Data(contentsOf: executable, options: .alwaysMapped) else { return false }
        return exe.range(of: Data("SteamClient0".utf8)) != nil
    }

    private static func hasSteamAPI(in installDir: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: installDir, includingPropertiesForKeys: nil) else { return false }
        for case let url as URL in enumerator {
            if url.lastPathComponent == ColdClientApplicator.folderName { enumerator.skipDescendants(); continue }
            let name = url.lastPathComponent.lowercased()
            if name == "steam_api.dll" || name == "steam_api64.dll" { return true }
        }
        return false
    }
}
