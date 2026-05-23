import Foundation

struct RuntimeRelease: Equatable {
    let tag: String
    let name: String
    let assetName: String
    let assetURL: URL
    let size: Int64
    let digest: String?
    let htmlURL: URL

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

@MainActor
final class RuntimeInstaller: ObservableObject {
    @Published private(set) var latestGPTK: RuntimeRelease?
    @Published private(set) var installedRuntime: RuntimeCandidate?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isInstalling = false
    @Published private(set) var statusMessage = "Ready"
    @Published var lastError: String?

    private let releaseURL = URL(string: "https://api.github.com/repos/Gcenx/game-porting-toolkit/releases/latest")!

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try AppPaths.ensureBaseDirectories()
            latestGPTK = try await fetchLatestGPTKRelease()
            installedRuntime = findManagedGPTRuntime()
            statusMessage = installedRuntime == nil ? "GPTK is not installed." : "GPTK runtime is installed."
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Could not refresh runtime catalog."
        }
    }

    func installLatestGPTK() async {
        guard !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }

        do {
            try AppPaths.ensureBaseDirectories()
            let release: RuntimeRelease
            if let latestGPTK {
                release = latestGPTK
            } else {
                release = try await fetchLatestGPTKRelease()
            }
            latestGPTK = release

            let installDirectory = AppPaths.runtimesDirectory
                .appendingPathComponent("GPTK-\(release.tag.safePathComponent)", isDirectory: true)
            let archiveURL = AppPaths.downloadsDirectory.appendingPathComponent(release.assetName)

            if let existing = findRuntime(in: installDirectory, displayName: "Managed GPTK \(release.tag)") {
                installedRuntime = existing
                statusMessage = "GPTK \(release.tag) is already installed."
                return
            }

            statusMessage = "Downloading \(release.assetName) (\(release.displaySize))..."
            try await download(from: release.assetURL, to: archiveURL)

            if let digest = release.digest, digest.hasPrefix("sha256:") {
                statusMessage = "Verifying archive..."
                let expected = String(digest.dropFirst("sha256:".count))
                let actual = try SHA256Digest.fileHexDigest(archiveURL)
                guard expected.caseInsensitiveCompare(actual) == .orderedSame else {
                    throw RuntimeInstallerError.digestMismatch
                }
            }

            statusMessage = "Extracting runtime..."
            if FileManager.default.fileExists(atPath: installDirectory.path) {
                try FileManager.default.removeItem(at: installDirectory)
            }
            try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
            try await extract(archiveURL: archiveURL, destination: installDirectory)

            guard let runtime = findRuntime(in: installDirectory, displayName: "Managed GPTK \(release.tag)") else {
                throw RuntimeInstallerError.runtimeNotFound
            }

            installedRuntime = runtime
            statusMessage = "Installed \(runtime.displayName)."
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Install failed."
        }
    }

    private func fetchLatestGPTKRelease() async throws -> RuntimeRelease {
        var request = URLRequest(url: releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw RuntimeInstallerError.releaseFetchFailed
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".tar.xz") }),
              let assetURL = URL(string: asset.browserDownloadURL),
              let htmlURL = URL(string: release.htmlURL) else {
            throw RuntimeInstallerError.assetNotFound
        }

        return RuntimeRelease(
            tag: release.tagName,
            name: release.name.isEmpty ? release.tagName : release.name,
            assetName: asset.name,
            assetURL: assetURL,
            size: Int64(asset.size),
            digest: asset.digest,
            htmlURL: htmlURL
        )
    }

    private func download(from source: URL, to destination: URL) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: source)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw RuntimeInstallerError.downloadFailed
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private func extract(archiveURL: URL, destination: URL) async throws {
        let result = try await ShellRunner.run(
            executable: "/usr/bin/tar",
            arguments: ["-xf", archiveURL.path, "-C", destination.path],
            environment: [:],
            outputHandler: { _ in }
        )
        guard result.exitCode == 0 else {
            throw RuntimeInstallerError.extractionFailed(result.output)
        }
    }

    private func findManagedGPTRuntime() -> RuntimeCandidate? {
        guard let release = latestGPTK else {
            return findRuntime(in: AppPaths.runtimesDirectory, displayName: "Managed GPTK")
        }
        let installDirectory = AppPaths.runtimesDirectory
            .appendingPathComponent("GPTK-\(release.tag.safePathComponent)", isDirectory: true)
        return findRuntime(in: installDirectory, displayName: "Managed GPTK \(release.tag)")
    }

    private func findRuntime(in directory: URL, displayName: String) -> RuntimeCandidate? {
        ManagedRuntimeScanner.findRuntime(in: directory, displayName: displayName)
    }
}

enum ManagedRuntimeScanner {
    static func findAll() -> [RuntimeCandidate] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: AppPaths.runtimesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.compactMap { child in
            findRuntime(in: child, displayName: "Managed \(child.lastPathComponent)")
        }
    }

    static func findRuntime(in directory: URL, displayName: String) -> RuntimeCandidate? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }

        if let runtime = RuntimeBundle.candidateIfAvailable(in: directory, fallbackDisplayName: displayName) {
            return runtime
        }

        let preferredNames = ["gameportingtoolkit", "wine64", "wine"]
        var matches: [(String, URL)] = []

        if let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isExecutableKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if let runtime = RuntimeBundle.candidateIfAvailable(in: url, fallbackDisplayName: displayName) {
                    return runtime
                }

                guard preferredNames.contains(url.lastPathComponent),
                      FileManager.default.isExecutableFile(atPath: url.path) else {
                    continue
                }
                matches.append((url.lastPathComponent, url))
            }
        }

        for name in preferredNames {
            if let match = matches.first(where: { $0.0 == name }) {
                let kind: RuntimeKind = name == "gameportingtoolkit" ? .gamePortingToolkit : .systemWine
                return RuntimeCandidate(kind: kind, executablePath: match.1.path, displayName: displayName)
            }
        }

        return nil
    }
}

private enum RuntimeInstallerError: LocalizedError {
    case releaseFetchFailed
    case assetNotFound
    case downloadFailed
    case digestMismatch
    case extractionFailed(String)
    case runtimeNotFound

    var errorDescription: String? {
        switch self {
        case .releaseFetchFailed:
            "Could not fetch the latest GPTK release from GitHub."
        case .assetNotFound:
            "The latest GPTK release does not include a downloadable .tar.xz asset."
        case .downloadFailed:
            "The GPTK runtime download failed."
        case .digestMismatch:
            "The downloaded GPTK archive did not match GitHub's SHA-256 digest."
        case .extractionFailed(let output):
            output.isEmpty ? "Could not extract the GPTK archive." : "Could not extract the GPTK archive: \(output)"
        case .runtimeNotFound:
            "The archive extracted, but no usable wine, wine64, or gameportingtoolkit executable was found."
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String
    let htmlURL: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let size: Int
    let digest: String?
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case digest
        case browserDownloadURL = "browser_download_url"
    }
}

private extension String {
    var safePathComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}
