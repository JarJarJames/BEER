import Foundation

extension ToolchainDetector {
    /// The runtime new games get. Existing games keep the one they have.
    var preferredGameRuntime: RuntimeCandidate? {
        Self.preferredGameRuntime(
            in: candidates,
            macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            manifest: ManagedRuntimeScanner.manifest(forWineBinary:)
        )
    }

    /// BEER's own GPTK builds first (the newest, where this macOS can run
    /// it), then any other GPTK (fastest, D3DMetal), then whatever is
    /// installed. Managed GPTK runtimes are named "Managed GPTK-…" but resolve
    /// to a wine64 executable (kind .systemWine), so GPTK is matched by name
    /// as well as kind.
    static func preferredGameRuntime(
        in candidates: [RuntimeCandidate],
        macOSMajorVersion: Int,
        manifest: (String) -> BEERRuntimeManifest?
    ) -> RuntimeCandidate? {
        var beerBuilds: [RuntimeCandidate] = []
        var usable: [RuntimeCandidate] = []
        for candidate in candidates {
            guard let found = manifest(candidate.executablePath) else {
                usable.append(candidate)
                continue
            }
            // A BEER build this macOS can't run is never offered.
            guard found.minimumMacOS <= macOSMajorVersion else { continue }
            beerBuilds.append(candidate)
            usable.append(candidate)
        }
        if let newest = beerBuilds.max(by: { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }) {
            return newest
        }
        return usable.first { $0.displayName.localizedCaseInsensitiveContains("GPTK") || $0.displayName.localizedCaseInsensitiveContains("Game Porting") }
            ?? usable.first { $0.kind == .gamePortingToolkit }
            ?? usable.first
    }
}
