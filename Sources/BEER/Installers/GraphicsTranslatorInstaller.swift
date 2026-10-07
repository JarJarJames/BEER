import Foundation

// Downloads D3D→Metal/Vulkan translation layers and installs their DLLs into a
// bottle's Wine prefix, so games that can't use Wine's built-in WineD3D
// (D3D→OpenGL, dead on modern macOS) get a working renderer.
//
//   • DXVK  (Gcenx/DXVK-macOS)  — D3D10/11 → Vulkan (MoltenVK). Clean drop-in:
//     just PE DLLs into system32/syswow64.
//   • DXMT  (3Shain/dxmt)        — D3D10/11 → Metal directly (no Vulkan). Also
//     ships a host-side winemetal.so that Wine finds via WINEDLLPATH (set in
//     BottleStore.environment for the dxmt backend).
//
// D3DMetal is deliberately NOT here — it's Apple's, bundled only inside GPTK's
// Wine, so it isn't installable into mainline Wine (and isn't offered there).

@MainActor
final class GraphicsTranslatorInstaller: ObservableObject {
    @Published private(set) var installed: Set<GraphicsTranslator> = []
    @Published private(set) var busy: GraphicsTranslator? = nil
    @Published private(set) var statusMessage = ""
    @Published var lastError: String?

    func refresh() {
        installed = Set(GraphicsTranslator.allCases.filter { isDownloaded($0) })
    }

    /// True if the translator is downloaded AND complete (has dxgi.dll). The
    /// dxgi check invalidates an earlier stripped DXVK build that lacked it, so
    /// it gets re-fetched as the full package.
    func isDownloaded(_ t: GraphicsTranslator) -> Bool {
        guard let dir = windowsDLLDirectory(in: t.installDirectory) else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("dxgi.dll").path)
    }

    /// Download + extract a translator into Application Support (idempotent).
    func ensureDownloaded(_ t: GraphicsTranslator) async throws {
        if isDownloaded(t) { return }
        busy = t
        defer { busy = nil }

        statusMessage = "Fetching \(t.displayName)…"
        let asset = try await latestBuiltinAsset(for: t)

        try FileManager.default.createDirectory(at: AppPaths.downloadsDirectory, withIntermediateDirectories: true)
        let archive = AppPaths.downloadsDirectory.appendingPathComponent(asset.name)
        statusMessage = "Downloading \(asset.name)…"
        try await download(from: asset.url, to: archive)

        statusMessage = "Extracting \(t.displayName)…"
        let dir = t.installDirectory
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await extract(archive: archive, to: dir)

        guard isDownloaded(t) else {
            throw GraphicsTranslatorError.dllsNotFound(t.displayName)
        }
        refresh()
        statusMessage = "\(t.displayName) ready."
    }

    /// Ensure the backend's translator is downloaded, then copy its DLLs into
    /// the bottle's prefix. No-op for backends that don't need a translator.
    func apply(_ backend: GraphicsBackend, to bottle: Bottle) async throws {
        guard let t = GraphicsTranslator.from(backend) else { return }
        try await ensureDownloaded(t)
        try copyDLLs(t, into: bottle)
        // DXVK talks to MoltenVK; the stock Gcenx MoltenVK crashes on
        // "disabling primitive restart". Swap in Khronos' private-API build.
        if backend == .dxvk {
            try await ensurePrivateAPIMoltenVK(forRuntimePath: bottle.runtimePath)
        }
    }

    // MARK: - Private-API MoltenVK (for DXVK on managed mainline Wine)

    /// Replace a managed Wine runtime's libMoltenVK.dylib with Khronos' official
    /// private-API build, which can disable primitive restart (the wall DXVK
    /// hits on Unity/D3D11 games). Idempotent; backs up the original; only
    /// touches runtimes we manage (CrossOver/system Wine ship their own).
    func ensurePrivateAPIMoltenVK(forRuntimePath runtimePath: String) async throws {
        guard runtimePath.hasPrefix(AppPaths.runtimesDirectory.path) else { return }
        guard let dylib = locateRuntimeMoltenVK(runtimePath: runtimePath) else { return } // GPTK has none
        let dir = dylib.deletingLastPathComponent()
        let sentinel = dir.appendingPathComponent(".gn-privateapi-moltenvk")
        if FileManager.default.fileExists(atPath: sentinel.path) { return }

        statusMessage = "Installing private-API MoltenVK…"
        let source = try await ensurePrivateAPIMoltenVKDownloaded()

        let fm = FileManager.default
        let backup = dir.appendingPathComponent("libMoltenVK.dylib.gn-orig")
        if !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: dylib, to: backup) }
        if fm.fileExists(atPath: dylib.path) { try fm.removeItem(at: dylib) }
        try fm.copyItem(at: source, to: dylib)
        // Apple Silicon won't load an unsigned dylib — ad-hoc sign it.
        _ = try? await ShellRunner.run(
            executable: "/usr/bin/codesign",
            arguments: ["--force", "--sign", "-", dylib.path],
            environment: [:], outputHandler: { _ in }
        )
        try? "privateapi".write(to: sentinel, atomically: true, encoding: .utf8)
        statusMessage = "Private-API MoltenVK ready."
    }

    /// Find `libMoltenVK.dylib` inside the managed runtime that owns this wine
    /// binary. nil if the runtime has none (e.g. GPTK uses D3DMetal, no Vulkan).
    private func locateRuntimeMoltenVK(runtimePath: String) -> URL? {
        let fm = FileManager.default
        // Walk up to the runtime's top-level folder (direct child of Runtimes/).
        var root = URL(fileURLWithPath: runtimePath)
        let runtimes = AppPaths.runtimesDirectory.standardizedFileURL.path
        while root.deletingLastPathComponent().standardizedFileURL.path != runtimes && root.pathComponents.count > 2 {
            root = root.deletingLastPathComponent()
        }
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in e where url.lastPathComponent == "libMoltenVK.dylib" {
            return url
        }
        return nil
    }

    private func ensurePrivateAPIMoltenVKDownloaded() async throws -> URL {
        let dir = AppPaths.translatorsDirectory.appendingPathComponent("MoltenVK-privateapi", isDirectory: true)
        if let existing = findFile(named: "libMoltenVK.dylib", in: dir) { return existing }

        // Scan releases for the macos-privateapi asset (latest stable has it).
        guard let url = URL(string: "https://api.github.com/repos/KhronosGroup/MoltenVK/releases?per_page=10") else {
            throw GraphicsTranslatorError.releaseFetchFailed("MoltenVK")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GraphicsTranslatorError.releaseFetchFailed("MoltenVK")
        }
        let releases = try JSONDecoder().decode([GHRelease].self, from: data)
        var asset: GHAsset?
        for release in releases {
            if let a = release.assets.first(where: { $0.name.contains("macos-privateapi") }) { asset = a; break }
        }
        guard let asset, let assetURL = URL(string: asset.browserDownloadURL) else {
            throw GraphicsTranslatorError.assetNotFound("MoltenVK private-API")
        }

        statusMessage = "Downloading private-API MoltenVK…"
        let archive = AppPaths.downloadsDirectory.appendingPathComponent(asset.name)
        try FileManager.default.createDirectory(at: AppPaths.downloadsDirectory, withIntermediateDirectories: true)
        try await download(from: assetURL, to: archive)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await extract(archive: archive, to: dir)

        guard let dylib = findFile(named: "libMoltenVK.dylib", in: dir) else {
            throw GraphicsTranslatorError.dllsNotFound("MoltenVK private-API")
        }
        return dylib
    }

    private func findFile(named name: String, in root: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in e where url.lastPathComponent == name { return url }
        return nil
    }

    // MARK: - Copy DLLs into the prefix

    private func copyDLLs(_ t: GraphicsTranslator, into bottle: Bottle) throws {
        let fm = FileManager.default
        let prefix = AppPaths.prefixURL(for: bottle)
        let system32 = prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = prefix.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)

        guard let win64 = windowsDLLDirectory(in: t.installDirectory) else {
            throw GraphicsTranslatorError.dllsNotFound(t.displayName)
        }
        // 32-bit sibling: DXMT uses "i386-windows", DXVK uses "x32".
        let win32Name = win64.lastPathComponent == "x64" ? "x32" : "i386-windows"
        let win32 = win64.deletingLastPathComponent().appendingPathComponent(win32Name, isDirectory: true)

        try fm.createDirectory(at: system32, withIntermediateDirectories: true)
        try copyDLLs(from: win64, into: system32)
        if fm.fileExists(atPath: win32.path) {
            try fm.createDirectory(at: syswow64, withIntermediateDirectories: true)
            try copyDLLs(from: win32, into: syswow64)
        }
    }

    private func copyDLLs(from source: URL, into dest: URL) throws {
        let fm = FileManager.default
        let dlls = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        for dll in dlls where dll.pathExtension.lowercased() == "dll" {
            let target = dest.appendingPathComponent(dll.lastPathComponent)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: dll, to: target)
        }
    }

    /// The directory holding `winemetal.so` for DXMT, so BottleStore can put it
    /// on WINEDLLPATH. nil if not present.
    func unixLibDirectory(for t: GraphicsTranslator) -> URL? {
        guard let win64 = windowsDLLDirectory(in: t.installDirectory) else { return nil }
        let unix = win64.deletingLastPathComponent().appendingPathComponent("x86_64-unix", isDirectory: true)
        return FileManager.default.fileExists(atPath: unix.path) ? unix : nil
    }

    /// Find the 64-bit DLL dir inside an extracted translator. DXMT uses
    /// `x86_64-windows`, DXVK uses `x64`. The top folder name carries the
    /// version, so we search rather than hardcode.
    private func windowsDLLDirectory(in root: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in e where url.lastPathComponent == "x86_64-windows" || url.lastPathComponent == "x64" {
            return url
        }
        return nil
    }

    // MARK: - Networking

    private struct Asset { let name: String; let url: URL }

    private func latestBuiltinAsset(for t: GraphicsTranslator) async throws -> Asset {
        // Scan the releases LIST (not /latest): for DXVK the full package lives
        // in an older tag than the latest stripped "-repack" release.
        guard let url = URL(string: "https://api.github.com/repos/\(t.repo)/releases?per_page=20") else {
            throw GraphicsTranslatorError.releaseFetchFailed(t.repo)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GraphicsTranslatorError.releaseFetchFailed(t.repo)
        }
        let releases = try JSONDecoder().decode([GHRelease].self, from: data)
        for release in releases {
            if let asset = release.assets.first(where: { t.matchesAsset($0.name) }),
               let assetURL = URL(string: asset.browserDownloadURL) {
                return Asset(name: asset.name, url: assetURL)
            }
        }
        throw GraphicsTranslatorError.assetNotFound(t.repo)
    }

    private func download(from source: URL, to destination: URL) async throws {
        let (tmp, response) = try await URLSession.shared.download(from: source)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GraphicsTranslatorError.downloadFailed
        }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: tmp, to: destination)
    }

    private func extract(archive: URL, to destination: URL) async throws {
        let result = try await ShellRunner.run(
            executable: "/usr/bin/tar",
            arguments: ["-xf", archive.path, "-C", destination.path],
            environment: [:],
            outputHandler: { _ in }
        )
        guard result.exitCode == 0 else {
            throw GraphicsTranslatorError.extractionFailed(result.output)
        }
    }

    private struct GHRelease: Decodable {
        let assets: [GHAsset]
    }
    private struct GHAsset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey { case name; case browserDownloadURL = "browser_download_url" }
    }
}
