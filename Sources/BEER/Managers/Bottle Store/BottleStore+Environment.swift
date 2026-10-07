import AppKit
import Foundation

extension BottleStore {
    func isRuntimeBundleBottle(_ bottle: Bottle) -> Bool {
        bottle.runtimeKind == .gameNativeWine || bottle.runtimeBundlePath != nil
    }

    func runtimeWinePath(for bottle: Bottle) -> String {
        bottle.runtimeEntrypoints?.wine ?? bottle.runtimePath
    }

    func runtimeWinebootPath(for bottle: Bottle) -> String? {
        if let wineboot = bottle.runtimeEntrypoints?.wineboot,
           FileManager.default.isExecutableFile(atPath: wineboot) {
            return wineboot
        }

        let sibling = URL(fileURLWithPath: runtimeWinePath(for: bottle))
            .deletingLastPathComponent()
            .appendingPathComponent("wineboot")
            .path
        return FileManager.default.isExecutableFile(atPath: sibling) ? sibling : nil
    }

    func runtimeWineserverPath(for bottle: Bottle) -> String? {
        if let wineserver = bottle.runtimeEntrypoints?.wineserver,
           FileManager.default.isExecutableFile(atPath: wineserver) {
            return wineserver
        }

        let sibling = URL(fileURLWithPath: runtimeWinePath(for: bottle))
            .deletingLastPathComponent()
            .appendingPathComponent("wineserver")
            .path
        return FileManager.default.isExecutableFile(atPath: sibling) ? sibling : nil
    }

    func environment(for bottle: Bottle, prefix: URL) -> [String: String] {
        var env = bottle.environmentOverrides
        let runtimeDirectory = runtimeBinDirectory(for: bottle)
        let inheritedPath = env["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"

        env["WINEPREFIX"] = prefix.path
        env["WINEARCH"] = "win64"
        // Pin the Wine username to "crossover" for ALL runtimes so the user
        // home — and therefore every game's save path
        // (drive_c/users/<name>/…) — is identical no matter which Wine the
        // bottle runs on.
        //
        // Why "crossover" specifically (and not, say, "beer"): Apple's
        // GPTK is built on CrossOver's Wine and hardcodes the user "crossover"
        // regardless of $USER. Mainline Wine instead uses the macOS login name.
        // If those differ, switching a bottle's runtime strands its saves in a
        // different users/ folder. We match GPTK's fixed name so saves line up
        // across runtimes with zero migration. This is NOT a CrossOver
        // dependency or endorsement — purely a compatibility constant.
        env["USER"] = "crossover"
        env["USERNAME"] = "crossover"
        env["WINEDLLOVERRIDES"] = dllOverrides(
            for: bottle.effectiveGraphicsBackend,
            controllerFix: bottle.effectiveControllerFix,
            userOverrides: bottle.environmentOverrides["WINEDLLOVERRIDES"]
        )
        env["WINEDEBUG"] = env["WINEDEBUG"] ?? "-all"
        env["WINEESYNC"] = env["WINEESYNC"] ?? "1"
        env["PATH"] = "\(runtimeDirectory):\(inheritedPath)"

        let libraryPaths = runtimeLibraryDirectories(for: bottle)
        if !libraryPaths.isEmpty {
            let inheritedLibraryPath = env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ProcessInfo.processInfo.environment["DYLD_FALLBACK_LIBRARY_PATH"]
            env["DYLD_FALLBACK_LIBRARY_PATH"] = (libraryPaths + [inheritedLibraryPath].compactMap { $0 })
                .filter { !$0.isEmpty }
                .joined(separator: ":")
        }

        switch bottle.effectiveGraphicsBackend {
        case .d3dMetal:
            env["MTL_HUD_ENABLED"] = env["MTL_HUD_ENABLED"] ?? "0"
        case .dxmt:
            env["DXMT_CONFIG"] = env["DXMT_CONFIG"] ?? "hud=0"
            if let unix = dxmtUnixLibDirectory() {
                let existing = env["WINEDLLPATH"].map { "\($0):" } ?? ""
                env["WINEDLLPATH"] = existing + unix
            }
        case .dxvk:
            env["DXVK_HUD"] = env["DXVK_HUD"] ?? "0"
            // Lets MoltenVK use Metal's private API so it can disable primitive
            // restart (and other features DXVK needs) — without this, pipelines
            // fail with "Metal does not support disabling primitive restart".
            env["MVK_CONFIG_USE_METAL_PRIVATE_API"] = env["MVK_CONFIG_USE_METAL_PRIVATE_API"] ?? "1"
        case .automatic, .wineD3D:
            break
        }

        return env
    }

    func runtimeBinDirectory(for bottle: Bottle) -> String {
        if let runtimeBundlePath = bottle.runtimeBundlePath {
            return URL(fileURLWithPath: runtimeBundlePath, isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .path
        }

        return URL(fileURLWithPath: runtimeWinePath(for: bottle))
            .deletingLastPathComponent()
            .path
    }

    func runtimeLibraryDirectories(for bottle: Bottle) -> [String] {
        var candidates: [URL] = []

        if let runtimeBundlePath = bottle.runtimeBundlePath {
            let bundleURL = URL(fileURLWithPath: runtimeBundlePath, isDirectory: true)
            candidates.append(bundleURL.appendingPathComponent("lib", isDirectory: true))
            candidates.append(bundleURL.appendingPathComponent("Frameworks", isDirectory: true))
        }

        let executableURL = URL(fileURLWithPath: runtimeWinePath(for: bottle))
        let binDirectory = executableURL.deletingLastPathComponent()
        let wineRoot = binDirectory.deletingLastPathComponent()
        candidates.append(wineRoot.appendingPathComponent("lib", isDirectory: true))
        candidates.append(wineRoot.appendingPathComponent("lib/external", isDirectory: true))
        candidates.append(wineRoot.appendingPathComponent("Frameworks", isDirectory: true))

        var seen: Set<String> = []
        return candidates
            .map(\.path)
            .filter { FileManager.default.fileExists(atPath: $0) }
            .filter { seen.insert($0).inserted }
    }

    /// DLL overrides for a launch: the graphics backend's translator DLLs, the
    /// GameInput preference, then whatever the bottle's own environment asks
    /// for — the user's entry goes last so it wins any conflict. (Previously
    /// this value overwrote `environmentOverrides["WINEDLLOVERRIDES"]`, so a
    /// user override was silently discarded.)
    func dllOverrides(for backend: GraphicsBackend, controllerFix: Bool, userOverrides: String?) -> String {
        var entries: [String] = []

        switch backend {
        case .automatic: break
        case .d3dMetal: entries.append("d3d12,d3d11,dxgi=n,b")
        case .dxmt: entries.append("d3d11,d3d10core,dxgi,winemetal=n,b")
        case .dxvk: entries.append("dxgi,d3d11,d3d10core,d3d9=n,b")
        case .wineD3D: entries.append("d3d11,dxgi,d3d12=b")
        }

        // Prefer native input DLLs when a bottle has them beside the executable.
        // Both are "n,b", so a bottle without them falls back to Wine's builtins
        // and nothing changes.
        //
        // gameinput: Wine's builtin is a stub whose GameInputCreate returns
        // E_NOTIMPL, so GDK-era titles that detect controllers through GameInput
        // (Kingdom Come: Deliverance II, Stalker 2) report zero pads.
        //
        entries.append("gameinput=n,b")

        // hid: only when the per-game controller fix is on, so a bottle that
        // does not need it never loads the shim — see ControllerSupport.
        if controllerFix { entries.append("hid=n,b") }

        if let userOverrides, !userOverrides.isEmpty { entries.append(userOverrides) }
        return entries.joined(separator: ";")
    }

    /// DXMT ships a host-side `winemetal.so`; point Wine at it via WINEDLLPATH
    /// so it loads alongside the winemetal.dll we copied into the prefix.
    func dxmtUnixLibDirectory() -> String? {
        let root = AppPaths.translatorsDirectory.appendingPathComponent("DXMT", isDirectory: true)
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in e where url.lastPathComponent == "x86_64-unix" {
            return url.path
        }
        return nil
    }
}
