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
    /// Bytes downloaded so far while the archive downloads; nil otherwise.
    @Published private(set) var downloadProgress: ByteProgress?
    @Published private(set) var statusMessage = "Ready"
    @Published var lastError: String?

    /// Fetches a GitHub API URL. Swappable so tests can answer without the network.
    private let fetch: (URLRequest) async throws -> (Data, URLResponse)
    private let macOSMajorVersion: Int

    init(
        fetch: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) },
        macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    ) {
        self.fetch = fetch
        self.macOSMajorVersion = macOSMajorVersion
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try AppPaths.ensureBaseDirectories()
            try await loadCatalog()
            installedRuntime = findManagedGPTRuntime()
            statusMessage = installedRuntime == nil ? "GPTK is not installed." : "GPTK runtime is installed."
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Could not refresh runtime catalog."
        }
    }

    /// The downloadable GPTK and Wine builds. Network only, no disk.
    func loadCatalog() async throws {
        // BEER's own builds lead (and so become `latestGPTK`, the one the game
        // page offers) where this macOS can run them. They're a best-effort
        // extra: Gcenx's list still loads if they can't.
        var beerReleases: [RuntimeRelease] = []
        if macOSMajorVersion >= RuntimeSources.beerGPTKMinimumMacOS {
            beerReleases = (try? await fetchGPTKReleases(from: RuntimeSources.beerGPTKReleases)) ?? []
        }
        availableReleases = beerReleases + (try await fetchGPTKReleases(from: RuntimeSources.gcenxGPTKReleases))
        latestGPTK = availableReleases.first
        // Wine builds are a best-effort extra catalog — don't fail the whole
        // refresh if that repo's API hiccups.
        availableWineBuilds = (try? await fetchWineBuilds()) ?? availableWineBuilds
    }

    /// Is this release already extracted into Application Support?
    func isInstalled(_ release: RuntimeRelease) -> Bool {
        findRuntime(in: installDirectory(for: release), displayName: release.managedDisplayName) != nil
    }

    /// Installs the GPTK the game page offers when no runtime is installed:
    /// BEER's own build where this macOS can run it, else Gcenx's newest.
    func installLatestGPTK() async {
        if latestGPTK == nil { await refresh() }
        guard let latestGPTK else {
            statusMessage = "Could not fetch the latest GPTK release."
            return
        }
        await install(latestGPTK)
    }

    /// Download + verify + extract a specific GPTK release into its own versioned
    /// directory. Multiple versions can coexist; the bottle picker lists them all.
    func install(_ release: RuntimeRelease) async {
        guard !isInstalling else { return }
        isInstalling = true
        installingTag = release.tag
        defer { isInstalling = false; installingTag = nil; downloadProgress = nil }

        do {
            try AppPaths.ensureBaseDirectories()
            let installDirectory = installDirectory(for: release)
            let archiveURL = AppPaths.downloadsDirectory.appendingPathComponent(release.assetName)

            if let existing = findRuntime(in: installDirectory, displayName: release.managedDisplayName) {
                installedRuntime = existing
                statusMessage = "\(release.tag) is already installed."
                return
            }

            // The archive stays on disk while it unpacks next to it.
            if release.size > 0, let volume = DiskSpaceCheck.freeSpace(at: installDirectory),
               let shortfall = DiskSpaceCheck.shortfall(
                   installBytes: release.size * (1 + DiskSpaceLimits.runtimeExtractionFactor),
                   availableBytes: volume.availableBytes, volumeName: volume.name
               ) {
                throw RuntimeInstallerError.notEnoughSpace(shortfall)
            }

            statusMessage = "Downloading \(release.assetName) (\(release.displaySize))..."
            downloadProgress = ByteProgress(received: 0, expected: release.size)
            try await download(from: release.assetURL, to: archiveURL, expectedSize: release.size)
            downloadProgress = nil

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
        let releases = try await fetchReleases(from: RuntimeSources.gcenxWineBuilds)
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

    private func fetchReleases(from url: URL) async throws -> [GitHubRelease] {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw RuntimeInstallerError.releaseFetchFailed
        }
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    private func fetchGPTKReleases(from url: URL) async throws -> [RuntimeRelease] {
        try await fetchReleases(from: url).compactMap { release in
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

    private func download(from source: URL, to destination: URL, expectedSize: Int64) async throws {
        let response = try await FileDownload.run(from: source, to: destination) { received, expected in
            Task { @MainActor [weak self] in
                // A report arriving after the download finished is dropped.
                guard let self, self.downloadProgress != nil else { return }
                self.downloadProgress = ByteProgress(received: received, expected: expected > 0 ? expected : expectedSize)
            }
        }
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw RuntimeInstallerError.downloadFailed
        }
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
