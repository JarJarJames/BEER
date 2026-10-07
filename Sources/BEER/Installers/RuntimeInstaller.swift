import Foundation

@MainActor
final class RuntimeInstaller: ObservableObject {
    @Published private(set) var latestGPTK: RuntimeRelease?
    @Published private(set) var availableReleases: [RuntimeRelease] = []
    /// Mainline Wine builds (Gcenx/macOS_Wine_builds) — the fallback for games
    /// GPTK's older Wine base can't run (e.g. missing USER32 functions).
    @Published private(set) var availableWineBuilds: [RuntimeRelease] = []
    @Published private(set) var installedRuntime: RuntimeCandidate?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isInstalling = false
    /// The tag currently being downloaded/installed, so the UI can show progress
    /// on the right row.
    @Published private(set) var installingTag: String?
    @Published private(set) var statusMessage = "Ready"
    @Published var lastError: String?

    private let releaseURL = URL(string: "https://api.github.com/repos/Gcenx/game-porting-toolkit/releases/latest")!
    private let releasesListURL = URL(string: "https://api.github.com/repos/Gcenx/game-porting-toolkit/releases?per_page=30")!
    private let wineBuildsURL = URL(string: "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases?per_page=8")!

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try AppPaths.ensureBaseDirectories()
            availableReleases = try await fetchAllGPTKReleases()
            latestGPTK = availableReleases.first
            // Wine builds are a best-effort extra catalog — don't fail the whole
            // refresh if that repo's API hiccups.
            availableWineBuilds = (try? await fetchWineBuilds()) ?? availableWineBuilds
            installedRuntime = findManagedGPTRuntime()
            statusMessage = installedRuntime == nil ? "GPTK is not installed." : "GPTK runtime is installed."
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Could not refresh runtime catalog."
        }
    }

    /// Is this release already extracted into Application Support?
    func isInstalled(_ release: RuntimeRelease) -> Bool {
        findRuntime(in: installDirectory(for: release), displayName: release.managedDisplayName) != nil
    }

    func installLatestGPTK() async {
        let release: RuntimeRelease
        if let latestGPTK {
            release = latestGPTK
        } else if let fetched = try? await fetchLatestGPTKRelease() {
            latestGPTK = fetched
            release = fetched
        } else {
            statusMessage = "Could not fetch the latest GPTK release."
            return
        }
        await install(release)
    }

    /// Download + verify + extract a specific GPTK release into its own versioned
    /// directory. Multiple versions can coexist; the bottle picker lists them all.
    func install(_ release: RuntimeRelease) async {
        guard !isInstalling else { return }
        isInstalling = true
        installingTag = release.tag
        defer { isInstalling = false; installingTag = nil }

        do {
            try AppPaths.ensureBaseDirectories()
            let installDirectory = installDirectory(for: release)
            let archiveURL = AppPaths.downloadsDirectory.appendingPathComponent(release.assetName)

            if let existing = findRuntime(in: installDirectory, displayName: release.managedDisplayName) {
                installedRuntime = existing
                statusMessage = "\(release.tag) is already installed."
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

            statusMessage = "Extracting \(release.tag)..."
            if FileManager.default.fileExists(atPath: installDirectory.path) {
                try FileManager.default.removeItem(at: installDirectory)
            }
            try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
            try await extract(archiveURL: archiveURL, destination: installDirectory)

            guard let runtime = findRuntime(in: installDirectory, displayName: release.managedDisplayName) else {
                throw RuntimeInstallerError.runtimeNotFound
            }

            installedRuntime = runtime
            statusMessage = "Installed \(runtime.displayName)."
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Install of \(release.tag) failed."
        }
    }

    private func installDirectory(for release: RuntimeRelease) -> URL {
        AppPaths.runtimesDirectory.appendingPathComponent(release.installDirName, isDirectory: true)
    }

    /// Fetch mainline Wine builds. Each release ships multiple variants
    /// (stable / devel / staging) as separate assets — we flatten them so each
    /// is its own installable entry.
    private func fetchWineBuilds() async throws -> [RuntimeRelease] {
        var request = URLRequest(url: wineBuildsURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw RuntimeInstallerError.releaseFetchFailed
        }
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        var out: [RuntimeRelease] = []
        for release in releases {
            guard let htmlURL = URL(string: release.htmlURL) else { continue }
            for asset in release.assets where asset.name.hasSuffix("-osx64.tar.xz") {
                guard let assetURL = URL(string: asset.browserDownloadURL) else { continue }
                let variant = asset.name
                    .replacingOccurrences(of: "-osx64.tar.xz", with: "")
                    .replacingOccurrences(of: "wine-", with: "")
                out.append(RuntimeRelease(
                    family: .wine,
                    tag: variant,
                    name: asset.name,
                    assetName: asset.name,
                    assetURL: assetURL,
                    size: Int64(asset.size),
                    digest: asset.digest,
                    htmlURL: htmlURL
                ))
            }
        }
        return out
    }

    private func fetchAllGPTKReleases() async throws -> [RuntimeRelease] {
        var request = URLRequest(url: releasesListURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw RuntimeInstallerError.releaseFetchFailed
        }
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        return releases.compactMap { release in
            guard let asset = release.assets.first(where: { $0.name.hasSuffix(".tar.xz") }),
                  let assetURL = URL(string: asset.browserDownloadURL),
                  let htmlURL = URL(string: release.htmlURL) else {
                return nil
            }
            return RuntimeRelease(
                family: .gptk,
                tag: release.tagName,
                name: release.name.isEmpty ? release.tagName : release.name,
                assetName: asset.name,
                assetURL: assetURL,
                size: Int64(asset.size),
                digest: asset.digest,
                htmlURL: htmlURL
            )
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
            family: .gptk,
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
