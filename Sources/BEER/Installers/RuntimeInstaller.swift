import Foundation

@MainActor @Observable
final class RuntimeInstaller {
    /// The GPTK the game page offers. Never a build this macOS can't run.
    private(set) var latestGPTK: RuntimeRelease?
    /// BEER's own GPTK builds, kept apart from Gcenx's. Includes ones this
    /// macOS can't run, so the Runtime Manager can show them greyed out.
    private(set) var beerReleases: [RuntimeRelease] = []
    /// Gcenx's GPTK builds.
    private(set) var availableReleases: [RuntimeRelease] = []
    /// Mainline Wine builds (Gcenx/macOS_Wine_builds) — the fallback for games
    /// GPTK's older Wine base can't run (e.g. missing USER32 functions).
    private(set) var availableWineBuilds: [RuntimeRelease] = []
    private(set) var installedRuntime: RuntimeCandidate?
    private(set) var isRefreshing = false
    private(set) var isInstalling = false
    /// The tag currently being downloaded/installed, so the UI can show progress
    /// on the right row.
    private(set) var installingTag: String?
    /// Bytes downloaded so far while the archive downloads; nil otherwise.
    private(set) var downloadProgress: ByteProgress?
    private(set) var statusMessage = "Ready"
    var lastError: String?

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
        // BEER's own builds are fetched on every macOS, so an older one can
        // still list them (greyed out). They're a best-effort extra: Gcenx's
        // list still loads if they can't.
        beerReleases = (try? await fetchBEERReleases()) ?? []
        availableReleases = try await fetchReleases(from: RuntimeSources.gcenxGPTKReleases).compactMap(gptkRelease(from:))
        // BEER's newest build this macOS can run leads, else Gcenx's newest.
        latestGPTK = beerReleases.first(where: canRun) ?? availableReleases.first
        // Wine builds are a best-effort extra catalog — don't fail the whole
        // refresh if that repo's API hiccups.
        availableWineBuilds = (try? await fetchWineBuilds()) ?? availableWineBuilds
    }

    /// Can this Mac's macOS run the release?
    func canRun(_ release: RuntimeRelease) -> Bool {
        release.runs(onMacOS: macOSMajorVersion)
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

    private func gptkRelease(from release: GitHubRelease) -> RuntimeRelease? {
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

    /// BEER's builds, each with the macOS it needs: from the release's
    /// `beer-runtime.json` asset where it has one (so a build that runs on an
    /// older macOS is offered there), else the constant.
    private func fetchBEERReleases() async throws -> [RuntimeRelease] {
        var out: [RuntimeRelease] = []
        for release in try await fetchReleases(from: RuntimeSources.beerGPTKReleases) {
            guard var runtime = gptkRelease(from: release) else { continue }
            runtime.minimumMacOS = await fetchManifest(of: release)?.minimumMacOS ?? RuntimeSources.beerGPTKMinimumMacOS
            out.append(runtime)
        }
        return out
    }

    private func fetchManifest(of release: GitHubRelease) async -> BEERRuntimeManifest? {
        guard let asset = release.assets.first(where: { $0.name == BEERRuntimeManifest.fileName }),
              let url = URL(string: asset.browserDownloadURL) else { return nil }
        do {
            let (data, response) = try await fetch(URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw RuntimeInstallerError.releaseFetchFailed
            }
            return try JSONDecoder().decode(BEERRuntimeManifest.self, from: data)
        } catch {
            // The constant stands in, which is what every build needed before
            // releases carried a manifest.
            Log.install.error("Couldn't read \(release.tagName, privacy: .public)'s runtime manifest: \(error.localizedDescription)")
            return nil
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
