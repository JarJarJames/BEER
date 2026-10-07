import Foundation

// Installs GBE_Fork (the actively-maintained Goldberg Steamworks emulator
// fork by Detanup01) into ~/Library/Application Support/BEER/Goldberg/.
//
// GBE_Fork ships a Windows .7z release containing replacement
// steam_api.dll (32-bit) and steam_api64.dll (64-bit) stubs. We extract
// them once and reuse for every game install. macOS's /usr/bin/tar is
// libarchive-based and handles .7z natively, so no third-party unpacker.
@MainActor
final class GoldbergInstaller: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var isInstalling = false
    @Published private(set) var statusMessage = "Checking Steam emulator…"
    @Published private(set) var installedVersion: String?
    @Published var lastError: String?

    private let releaseAPI = URL(string: "https://api.github.com/repos/Detanup01/gbe_fork/releases/latest")!

    var installDirectory: URL { AppPaths.goldbergDirectory }

    /// Path to the 64-bit stub we ship into game directories.
    var steamApi64URL: URL? {
        findStub(named: "steam_api64.dll")
    }

    /// Path to the 32-bit stub.
    var steamApi32URL: URL? {
        findStub(named: "steam_api.dll")
    }

    func refresh() {
        let ok = steamApi64URL != nil && steamApi32URL != nil
        isInstalled = ok
        statusMessage = ok
            ? "Steam emulator (GBE_Fork) installed."
            : "Steam emulator is not installed yet."
    }

    func install() async {
        guard !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }

        do {
            try AppPaths.ensureBaseDirectories()
            try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)

            statusMessage = "Looking up latest GBE_Fork release…"
            let release = try await fetchLatestRelease()
            installedVersion = release.tag

            statusMessage = "Downloading \(release.assetName) (\(release.size.fileSizeString))…"
            let archiveURL = installDirectory.appendingPathComponent(release.assetName)
            try await download(from: release.assetURL, to: archiveURL)

            statusMessage = "Extracting…"
            // macOS /usr/bin/tar is BSD tar / libarchive, which supports 7z.
            let extract = try await ShellRunner.run(
                executable: "/usr/bin/tar",
                arguments: ["-xf", archiveURL.path, "-C", installDirectory.path],
                environment: [:],
                outputHandler: { _ in }
            )
            guard extract.exitCode == 0 else {
                throw GoldbergInstallerError.extractionFailed(extract.output)
            }
            try? FileManager.default.removeItem(at: archiveURL)

            refresh()
            guard isInstalled else {
                throw GoldbergInstallerError.binariesNotFound
            }
            statusMessage = "Steam emulator (GBE_Fork \(release.tag)) installed."
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Install failed."
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: installDirectory)
        refresh()
    }

    /// Scan the install tree for a named DLL — GBE_Fork's archive layout has
    /// changed across releases (`release/x64/steam_api64.dll` historically,
    /// `experimental/...` sometimes); pick the first match we find. Prefer
    /// the `release` build over `experimental`/`debug` variants.
    private func findStub(named filename: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: installDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return nil }
        var matches: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent.lowercased() == filename.lowercased() {
            matches.append(url)
        }
        // Heuristic: prefer paths containing "/release/" or "/regular/" (the
        // non-experimental, non-debug "stable" build).
        if let preferred = matches.first(where: { p in
            let s = p.path.lowercased()
            return (s.contains("/release/") || s.contains("/regular/"))
                && !s.contains("/experimental")
                && !s.contains("/debug")
        }) {
            return preferred
        }
        return matches.first
    }

    // MARK: - GitHub release lookup

    private struct Release {
        let tag: String
        let assetName: String
        let assetURL: URL
        let size: Int64
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: releaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GoldbergInstallerError.releaseFetchFailed
        }
        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        // Pick the release Windows build, NOT debug, NOT vs22-specific.
        let preferred = payload.assets.first { a in
            a.name.lowercased().contains("emu-win-release.7z") &&
            !a.name.lowercased().contains("debug")
        }
        let fallback = payload.assets.first { $0.name.lowercased().contains("emu-win-release") }
        guard let asset = preferred ?? fallback,
              let url = URL(string: asset.browser_download_url) else {
            throw GoldbergInstallerError.assetNotFound
        }
        return Release(
            tag: payload.tag_name,
            assetName: asset.name,
            assetURL: url,
            size: Int64(asset.size)
        )
    }

    private func download(from source: URL, to destination: URL) async throws {
        let (tempURL, response) = try await URLSession.shared.download(from: source)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GoldbergInstallerError.downloadFailed
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let assets: [GitHubAsset]
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let size: Int
        let browser_download_url: String
    }
}
