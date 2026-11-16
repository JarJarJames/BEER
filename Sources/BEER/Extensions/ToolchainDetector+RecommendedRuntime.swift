import Foundation

extension ToolchainDetector {
    /// The runtime the Runtime Manager recommends for this Mac.
    func recommendedRuntime(beerReleases: [RuntimeRelease], gptkReleases: [RuntimeRelease]) -> RuntimeRecommendation? {
        Self.recommendedRuntime(
            installed: candidates,
            beerReleases: beerReleases,
            gptkReleases: gptkReleases,
            macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            manifest: { self.manifests[$0] }
        )
    }

    /// `preferredGameRuntime` run over the installed runtimes plus the GPTK
    /// releases not installed yet, each standing in as the runtime it would
    /// install as. So the recommendation, once installed, is exactly what new
    /// games get, and a BEER build this macOS can't run is never recommended.
    static func recommendedRuntime(
        installed: [RuntimeCandidate],
        beerReleases: [RuntimeRelease],
        gptkReleases: [RuntimeRelease],
        macOSMajorVersion: Int,
        manifest: (String) -> BEERRuntimeManifest?
    ) -> RuntimeRecommendation? {
        let installedNames = Set(installed.map(\.displayName))
        var releases: [String: RuntimeRelease] = [:]
        var releaseManifests: [String: BEERRuntimeManifest] = [:]
        var candidates = installed
        for release in beerReleases + gptkReleases {
            // The name ManagedRuntimeScanner gives the installed folder.
            let name = "Managed \(release.installDirName)"
            guard !installedNames.contains(name) else { continue }
            let key = "release:\(release.installDirName)"
            releases[key] = release
            if let minimumMacOS = release.minimumMacOS {
                // Only minimumMacOS is read; its presence marks a BEER build.
                releaseManifests[key] = BEERRuntimeManifest(d3dMetalVersion: "", crossOverSourceVersion: "", minimumMacOS: minimumMacOS)
            }
            candidates.append(RuntimeCandidate(kind: .systemWine, executablePath: key, displayName: name))
        }
        guard let pick = preferredGameRuntime(
            in: candidates,
            macOSMajorVersion: macOSMajorVersion,
            manifest: { releaseManifests[$0] ?? manifest($0) }
        ) else { return nil }
        return releases[pick.executablePath].map(RuntimeRecommendation.release) ?? .installed(pick)
    }
}
