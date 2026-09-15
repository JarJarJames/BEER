import Foundation

enum RuntimeKind: String, Codable, CaseIterable, Identifiable {
    case systemWine
    case crossOver
    case whisky
    case gamePortingToolkit
    case gameNativeWine
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .systemWine: "System Wine"
        case .crossOver: "CrossOver"
        case .whisky: "Whisky Wine"
        case .gamePortingToolkit: "Game Porting Toolkit"
        case .gameNativeWine: "GameNative Wine"
        case .custom: "Custom Wine"
        }
    }
}

enum GraphicsBackend: String, Codable, CaseIterable, Identifiable {
    case automatic
    case d3dMetal
    case dxmt
    case dxvk
    case wineD3D

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .d3dMetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wineD3D: "WineD3D"
        }
    }
}

enum DisplayResolutionMode: String, Codable, CaseIterable, Identifiable {
    case standard
    case highResolution

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .highResolution: "High Resolution"
        }
    }
}

struct RuntimeCandidate: Identifiable, Codable, Hashable {
    var id: String { bundlePath ?? executablePath }
    var kind: RuntimeKind
    var executablePath: String
    var displayName: String
    var bundlePath: String? = nil
    var version: String? = nil
    var entrypoints: RuntimeEntrypoints? = nil

    var parentDirectory: String {
        URL(fileURLWithPath: executablePath).deletingLastPathComponent().path
    }

    var locationPath: String {
        bundlePath ?? executablePath
    }
}

struct RuntimeEntrypoints: Codable, Hashable {
    var wine: String
    var wineboot: String?
    var wineserver: String?
}

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

struct SteamAccount: Codable, Equatable {
    var username: String           // Steam account/persona name once signed in
    var steamID64: String?
    var avatarURL: String?
    var isLoggedIn: Bool

    static let signedOut = SteamAccount(username: "", steamID64: nil, avatarURL: nil, isLoggedIn: false)
}

struct SteamLibraryGame: Identifiable, Codable, Hashable {
    var id: Int { appID }
    var appID: Int
    var name: String
    var headerImageURL: String?
    var iconURL: String?
    var sizeOnDiskBytes: Int64?
    var lastPlayed: Date?
    var installedBottleID: UUID?

    var headerImage: URL? {
        URL(string: headerImageURL ?? "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/header.jpg")
    }

    /// Steam's wide, high-resolution Library backdrop. Unlike `header.jpg`,
    /// this contains artwork without a baked-in oversized game logo.
    var libraryHeroImage: URL? {
        URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/library_hero.jpg")
    }

    /// Transparent title treatment Steam layers over its Library hero art.
    var libraryLogoImage: URL? {
        URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/logo.png")
    }
}

/// One DLC the user has turned on for a game. `hasContent` records whether the
/// DLC had a depot to download: licence-only DLC (season passes, artbooks) are
/// declared to the emulator but have no files on disk.
struct InstalledDLC: Codable, Hashable, Identifiable {
    var id: Int { appID }
    var appID: Int
    var name: String
    var hasContent: Bool
    var installedAt: Date

    /// The emulator's ini parser reads to end-of-line, so a name carrying a
    /// newline would corrupt the following entries.
    var iniSafeName: String {
        name.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

enum SteamGameInstallStatus: String, Codable {
    case notInstalled
    case queued
    case installing
    case installed
    case updateAvailable
    case failed
}

struct BottleLogEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let message: String
    let isError: Bool
}

enum RuntimeBundle {
    static func candidate(from url: URL, fallbackDisplayName: String? = nil) throws -> RuntimeCandidate {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw RuntimeBundleError.notDirectory
        }

        let manifestURL = url.appendingPathComponent("runtime.json", isDirectory: false)
        let manifest: RuntimeBundleManifest?
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(RuntimeBundleManifest.self, from: data)
        } else {
            manifest = nil
        }

        let entrypoints = try resolvedEntrypoints(for: url, manifest: manifest)
        guard FileManager.default.isExecutableFile(atPath: entrypoints.wine) else {
            throw RuntimeBundleError.missingExecutable(entrypoints.wine)
        }
        if let wineboot = entrypoints.wineboot,
           !FileManager.default.isExecutableFile(atPath: wineboot) {
            throw RuntimeBundleError.missingExecutable(wineboot)
        }
        if let wineserver = entrypoints.wineserver,
           !FileManager.default.isExecutableFile(atPath: wineserver) {
            throw RuntimeBundleError.missingExecutable(wineserver)
        }

        let version = manifest?.version
        let displayName = displayName(
            manifestName: manifest?.name,
            fallback: fallbackDisplayName ?? url.deletingPathExtension().lastPathComponent,
            version: version
        )

        return RuntimeCandidate(
            kind: .gameNativeWine,
            executablePath: entrypoints.wine,
            displayName: displayName,
            bundlePath: url.path,
            version: version,
            entrypoints: entrypoints
        )
    }

    static func candidateIfAvailable(in url: URL, fallbackDisplayName: String? = nil) -> RuntimeCandidate? {
        guard isRuntimeBundle(url) else { return nil }
        return try? candidate(from: url, fallbackDisplayName: fallbackDisplayName)
    }

    static func isRuntimeBundle(_ url: URL) -> Bool {
        let manifestURL = url.appendingPathComponent("runtime.json", isDirectory: false)
        return url.pathExtension == "runtime" || FileManager.default.fileExists(atPath: manifestURL.path)
    }

    private static func resolvedEntrypoints(for bundleURL: URL, manifest: RuntimeBundleManifest?) throws -> RuntimeEntrypoints {
        if let manifest {
            return RuntimeEntrypoints(
                wine: resolve(manifest.entrypoints.wine, relativeTo: bundleURL).path,
                wineboot: manifest.entrypoints.wineboot.map { resolve($0, relativeTo: bundleURL).path },
                wineserver: manifest.entrypoints.wineserver.map { resolve($0, relativeTo: bundleURL).path }
            )
        }

        let binURL = bundleURL.appendingPathComponent("bin", isDirectory: true)
        let wineURL = binURL.appendingPathComponent("wine", isDirectory: false)
        let winebootURL = binURL.appendingPathComponent("wineboot", isDirectory: false)
        let wineserverURL = binURL.appendingPathComponent("wineserver", isDirectory: false)

        return RuntimeEntrypoints(
            wine: wineURL.path,
            wineboot: FileManager.default.fileExists(atPath: winebootURL.path) ? winebootURL.path : nil,
            wineserver: FileManager.default.fileExists(atPath: wineserverURL.path) ? wineserverURL.path : nil
        )
    }

    private static func resolve(_ path: String, relativeTo bundleURL: URL) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return bundleURL.appendingPathComponent(path, isDirectory: false)
    }

    private static func displayName(manifestName: String?, fallback: String, version: String?) -> String {
        let rawName: String
        if let manifestName, !manifestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawName = manifestName
        } else {
            rawName = fallback
        }

        let baseName = rawName.localizedCaseInsensitiveContains("GameNativeWine") || rawName.localizedCaseInsensitiveContains("GameNative Wine")
            ? "GameNative Wine"
            : rawName

        guard let version, !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return baseName
        }
        return "\(baseName) \(version)"
    }
}

private struct RuntimeBundleManifest: Decodable {
    let name: String?
    let version: String?
    let entrypoints: RuntimeEntrypoints
}

enum RuntimeBundleError: LocalizedError {
    case notDirectory
    case missingExecutable(String)

    var errorDescription: String? {
        switch self {
        case .notDirectory:
            "The selected runtime is not a directory bundle."
        case .missingExecutable(let path):
            "The selected runtime bundle references a missing or non-executable file: \(path)"
        }
    }
}
