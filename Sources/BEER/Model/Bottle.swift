import Foundation

struct Bottle: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var runtimePath: String
    var runtimeKind: RuntimeKind
    var runtimeBundlePath: String?
    var runtimeDisplayName: String?
    var runtimeVersion: String?
    var runtimeEntrypoints: RuntimeEntrypoints?
    var graphicsBackend: GraphicsBackend
    var windowsVersion: String
    /// Retained only to migrate game arguments written by older builds. The
    /// retired full-Steam-client workflow no longer reads or writes this field.
    var launchArguments: String
    var environmentOverrides: [String: String]
    var notes: String

    // When this bottle was created by the library install flow, these
    // identify the Steam game it belongs to. Legacy bottles created via the
    // retired manual-bottle flow leave these nil.
    var steamAppID: Int? = nil
    var steamGameName: String? = nil
    var gameInstallStatus: SteamGameInstallStatus? = nil
    var gameLaunchExecutable: String? = nil
    /// Arguments passed to the installed game's executable. Optional so older
    /// bottle metadata still decodes.
    var gameLaunchArguments: String? = nil
    /// Host filesystem path to the game's install root (the directory that
    /// contains the game's own steam_api*.dll). Used by the Goldberg patcher
    /// when reapplying or restoring on an already-installed game.
    var gameInstallDirectory: String? = nil
    /// DLC the user has enabled for this game. Drives the `[app::dlcs]` block
    /// the Steam emulator reads, so the game is told it owns them. Optional so
    /// bottles written before the DLC manager still decode.
    var installedDLC: [InstalledDLC]? = nil

    // --- Display resolution ---
    // Retina mode makes Wine expose twice the macOS point dimensions to Windows
    // games. Optional so bottles written by older releases still decode.
    var displayResolutionMode: DisplayResolutionMode? = nil

    var effectiveDisplayResolutionMode: DisplayResolutionMode {
        displayResolutionMode ?? .standard
    }

    // --- Controller compatibility ---
    // Opt-in per game. Off by default: it rewrites what the game reads from the
    // HID device, which is only correct for pads Wine mishandles. See
    // `ControllerSupport` and `Tools/ControllerFix/README.md`.
    var controllerFix: Bool? = nil

    var effectiveControllerFix: Bool {
        controllerFix ?? false
    }

    var effectiveGameLaunchArguments: String {
        gameLaunchArguments ?? ""
    }

    var effectiveInstalledDLC: [InstalledDLC] {
        (installedDLC ?? []).sorted { $0.appID < $1.appID }
    }

    /// Move arguments entered through the old Steam-only field into the game
    /// field. Returns whether the bottle changed and needs to be persisted.
    mutating func migrateLegacyLibraryLaunchArguments() -> Bool {
        guard steamAppID != nil, !launchArguments.isEmpty else { return false }
        if gameLaunchArguments == nil && launchArguments != "-no-cef-sandbox" {
            gameLaunchArguments = launchArguments
        }
        launchArguments = ""
        return true
    }

    var folderName: String {
        "\(sanitizedName)-\(id.uuidString.prefix(8))"
    }

    private var sanitizedName: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped).replacingOccurrences(of: "--", with: "-")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty ? "Bottle" : collapsed
    }

    var runtimeLabel: String {
        runtimeDisplayName ?? runtimeKind.label
    }

    var runtimeLocationPath: String {
        runtimeBundlePath ?? runtimePath
    }

    /// True when this bottle runs on a GPTK-derived Wine (Apple's D3DMetal is
    /// present). Managed GPTK runtimes resolve to a wine64 exe (kind
    /// .systemWine), so we also match on the display name.
    var isGPTKRuntime: Bool {
        if runtimeKind == .gamePortingToolkit { return true }
        let n = (runtimeDisplayName ?? "")
        return n.localizedCaseInsensitiveContains("GPTK") || n.localizedCaseInsensitiveContains("Game Porting")
    }

    /// Graphics backends offered for this bottle, scoped to what actually works
    /// on its runtime:
    ///   • GPTK      — Apple D3DMetal (built in) + WineD3D.
    ///   • CrossOver — D3DMetal + DXVK (CrossOver ships a DXVK-aware DXGI).
    ///   • mainline Wine — DXMT (D3D→Metal, self-contained) + WineD3D. DXVK is
    ///     NOT offered: Gcenx's DXVK-macOS has no DXGI of its own and relies on
    ///     CrossOver's, so it can't enumerate a device on mainline Wine.
    var availableGraphicsBackends: [GraphicsBackend] {
        if isGPTKRuntime {
            return [.automatic, .d3dMetal, .wineD3D]
        }
        if runtimeKind == .crossOver {
            return [.automatic, .d3dMetal, .dxvk, .wineD3D]
        }
        // Mainline Wine: DXVK (ships its own DXGI) and DXMT both work.
        return [.automatic, .dxvk, .dxmt, .wineD3D]
    }

    /// The stored backend, coerced to a valid one for the current runtime.
    /// Prevents a stale selection (e.g. DXVK left over after switching to
    /// mainline Wine) from silently being applied.
    var effectiveGraphicsBackend: GraphicsBackend {
        availableGraphicsBackends.contains(graphicsBackend) ? graphicsBackend : .automatic
    }

    /// Reset the backend to a valid one when it no longer fits the runtime.
    mutating func normalizeGraphicsBackend() {
        if !availableGraphicsBackends.contains(graphicsBackend) {
            graphicsBackend = .automatic
        }
    }

    /// Rewrite stored absolute paths after the support dir was renamed
    /// (GameNativeMac → BEER). bottles.json holds baked absolute paths that the
    /// directory rename in AppPaths doesn't touch, so stale paths point at the
    /// now-gone old folder and games fail to launch. Returns true if changed.
    mutating func rewriteStoragePaths(from legacy: String, to current: String) -> Bool {
        var changed = false
        func fix(_ s: inout String) {
            guard s.contains(legacy) else { return }
            s = s.replacingOccurrences(of: legacy, with: current); changed = true
        }
        func fixOpt(_ s: inout String?) {
            guard var v = s else { return }
            fix(&v); s = v
        }
        fix(&runtimePath)
        fixOpt(&runtimeBundlePath)
        fixOpt(&gameInstallDirectory)
        fixOpt(&gameLaunchExecutable)
        if var e = runtimeEntrypoints {
            fix(&e.wine); fixOpt(&e.wineboot); fixOpt(&e.wineserver)
            runtimeEntrypoints = e
        }
        return changed
    }

    mutating func useRuntime(_ runtime: RuntimeCandidate) {
        runtimePath = runtime.executablePath
        runtimeKind = runtime.kind
        runtimeBundlePath = runtime.bundlePath
        runtimeDisplayName = runtime.displayName
        runtimeVersion = runtime.version
        runtimeEntrypoints = runtime.entrypoints
        normalizeGraphicsBackend()  // drop a backend the new runtime can't use
    }

    static func make(
        name: String,
        runtime: RuntimeCandidate,
        graphicsBackend: GraphicsBackend
    ) -> Bottle {
        Bottle(
            id: UUID(),
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            runtimePath: runtime.executablePath,
            runtimeKind: runtime.kind,
            runtimeBundlePath: runtime.bundlePath,
            runtimeDisplayName: runtime.displayName,
            runtimeVersion: runtime.version,
            runtimeEntrypoints: runtime.entrypoints,
            graphicsBackend: graphicsBackend,
            windowsVersion: "win10",
            launchArguments: "",
            environmentOverrides: [:],
            notes: ""
        )
    }
}

// ---------------------------------------------------------------------------
// App-level Steam account + per-game library entries
// ---------------------------------------------------------------------------
//
// Sign-in is QR-only (Steam Mobile App → SteamAuthStore). We never see the
// password. Games are downloaded by DepotDownloader and installed one-per-Wine
// bottle (Winlator/GameNative-Android style) so each can be tuned independently.
// This account is just the cached display identity; the credential lives in
// SteamCloudAccount (steam-cloud-auth.json).
