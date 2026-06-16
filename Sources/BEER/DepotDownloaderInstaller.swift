import Foundation

// Installs SteamRE/DepotDownloader (native macOS arm64 build) into
// ~/Library/Application Support/BEER/DepotDownloader/.
//
// DepotDownloader is a self-contained .NET 8 binary published by the same
// group that maintains SteamKit. It speaks Steam's binary CM protocol
// directly, supports QR code login, and caches refresh tokens for
// subsequent invocations — none of which SteamCMD can do.
//
// We pin against the GitHub releases API so the user always gets the
// current build, and we strip the macOS quarantine xattr so Gatekeeper
// doesn't block first-launch.
@MainActor
final class DepotDownloaderInstaller: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var isInstalling = false
    @Published private(set) var statusMessage = "Checking DepotDownloader…"
    @Published private(set) var installedVersion: String?
    @Published var lastError: String?

    private let releaseAPI = URL(string: "https://api.github.com/repos/SteamRE/DepotDownloader/releases/latest")!

    var installDirectory: URL { AppPaths.depotDownloaderDirectory }
    var executableURL: URL { AppPaths.depotDownloaderExecutableURL }

    func refresh() {
        let exists = FileManager.default.isExecutableFile(atPath: executableURL.path)
        isInstalled = exists
        statusMessage = exists
            ? "DepotDownloader is installed at \(installDirectory.path)."
            : "DepotDownloader is not installed yet."
    }

    func install() async {
        guard !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }

        do {
            try AppPaths.ensureBaseDirectories()
            try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)

            statusMessage = "Looking up latest DepotDownloader release…"
            let release = try await fetchLatestRelease()
            installedVersion = release.tag

            statusMessage = "Downloading \(release.assetName) (\(byteString(release.size)))…"
            let zipURL = installDirectory.appendingPathComponent(release.assetName)
            try await download(from: release.assetURL, to: zipURL)

            statusMessage = "Extracting…"
            let extract = try await ShellRunner.run(
                executable: "/usr/bin/unzip",
                arguments: ["-o", zipURL.path, "-d", installDirectory.path],
                environment: [:],
                outputHandler: { _ in }
            )
            guard extract.exitCode == 0 else {
                throw DepotDownloaderInstallerError.extractionFailed(extract.output)
            }
            try? FileManager.default.removeItem(at: zipURL)

            // The zip extracts to a flat layout: ./DepotDownloader + (sometimes)
            // ./*.dll alongside it. Make sure the binary is executable.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

            // Strip the macOS quarantine bit so Gatekeeper doesn't ask the user
            // to right-click → Open the first time. Failure here is non-fatal —
            // worst case, the user has to allow it once in System Settings.
            _ = try? await ShellRunner.run(
                executable: "/usr/bin/xattr",
                arguments: ["-dr", "com.apple.quarantine", installDirectory.path],
                environment: [:],
                outputHandler: { _ in }
            )

            refresh()
            guard isInstalled else {
                throw DepotDownloaderInstallerError.executableMissing
            }
            statusMessage = "DepotDownloader \(release.tag) installed."
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Install failed."
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: installDirectory)
        refresh()
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
            throw DepotDownloaderInstallerError.releaseFetchFailed
        }
        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let preferredName = "DepotDownloader-macos-arm64.zip"
        let intelName = "DepotDownloader-macos-x64.zip"
        let arm = payload.assets.first { $0.name == preferredName }
        let intel = payload.assets.first { $0.name == intelName }
        let chosen = arm ?? intel
        guard let asset = chosen, let url = URL(string: asset.browser_download_url) else {
            throw DepotDownloaderInstallerError.assetNotFound
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
            throw DepotDownloaderInstallerError.downloadFailed
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

enum DepotDownloaderInstallerError: LocalizedError {
    case releaseFetchFailed
    case assetNotFound
    case downloadFailed
    case extractionFailed(String)
    case executableMissing

    var errorDescription: String? {
        switch self {
        case .releaseFetchFailed: return "Could not look up the latest DepotDownloader release on GitHub."
        case .assetNotFound: return "The latest DepotDownloader release does not include a macOS arm64 zip."
        case .downloadFailed: return "Downloading DepotDownloader failed."
        case .extractionFailed(let detail):
            return detail.isEmpty ? "Could not extract DepotDownloader." : "Could not extract DepotDownloader:\n\(detail)"
        case .executableMissing: return "Extraction finished but the DepotDownloader binary was not present in the archive."
        }
    }
}
