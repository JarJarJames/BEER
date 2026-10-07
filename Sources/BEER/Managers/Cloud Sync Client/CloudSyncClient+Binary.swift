import Foundation

extension CloudSyncClient {
    /// Find the helper executable. Checked in order:
    ///   1. Next to / near the running app executable. The helper bundled with
    ///      this app build must win over a potentially stale standalone copy.
    ///   2. The dev build output, relative to the current working directory
    ///      (so `swift run` from the repo root just works).
    ///   3. App Support install dir (where scripts/build_cloudsync.sh puts it).
    /// Where the helper is, in the order it should be trusted:
    ///
    ///  1. next to the app binary — a shipped .app bundles its own helper, and
    ///     that copy always matches the app it was built with;
    ///  2. the SwiftPM prebuild plugin's output (Plugins/CloudSyncPrebuild) —
    ///     `swift build`/`swift run` republish this automatically whenever
    ///     Tools/CloudSync/ changes, so for local dev it's always at least as
    ///     fresh as what's on disk, no manual script run required;
    ///  3. the install in Application Support — what `build_cloudsync.sh`
    ///     writes, kept as a fallback for whoever still runs it by hand;
    ///  4. `Tools/CloudSync/publish/`, in case the helper was published but not
    ///     installed.
    ///
    /// Raw `dotnet build` output (`Tools/CloudSync/bin/…`) is deliberately NOT a
    /// candidate. It used to come second, ahead of the install, and since it is
    /// a complete runnable build that nothing ever refreshes, a stale copy there
    /// silently shadowed every rebuilt helper — the app kept running old code
    /// while the installed helper sat unused.
    static func locateBinary() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []

        let exeDir = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("CloudSync"))
        candidates.append(exeDir.appendingPathComponent("CloudSync/CloudSync"))

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        if let pluginOutput = locatePluginPublishedBinary(under: cwd) {
            candidates.append(pluginOutput)
        }

        candidates.append(AppPaths.cloudSyncExecutableURL)

        candidates.append(cwd.appendingPathComponent("Tools/CloudSync/publish/CloudSync"))

        guard let found = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) else { return nil }
        clearQuarantineIfNeeded(found)
        return found
    }

    /// Find the helper `Plugins/CloudSyncPrebuild` published under
    /// `.build/plugins/outputs/…`. The exact intermediate path segments are an
    /// SwiftPM implementation detail (they encode the package name and
    /// target), so this searches for the fixed suffix
    /// `CloudSyncPrebuild/CloudSyncPrebuildOutput/publish/CloudSync` rather
    /// than hardcoding the full path.
    static func locatePluginPublishedBinary(under cwd: URL) -> URL? {
        let outputsRoot = cwd.appendingPathComponent(".build/plugins/outputs")
        guard let enumerator = FileManager.default.enumerator(
            at: outputsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator where url.lastPathComponent == "CloudSync" {
            let parent = url.deletingLastPathComponent()
            guard parent.lastPathComponent == "publish" else { continue }
            if parent.deletingLastPathComponent().lastPathComponent == "CloudSyncPrebuildOutput" {
                return url
            }
        }
        return nil
    }

    /// Strip a stray `com.apple.quarantine` from the resolved helper binary.
    ///
    /// A distributed BEER.app downloaded through a browser gets every file
    /// inside it quarantined on extraction. Opening the .app through Finder
    /// clears that flag for the app itself, but this helper is launched via
    /// `Process()`, not LaunchServices, and macOS doesn't reliably propagate
    /// the "approved to run" clearing to it — so it can keep the flag
    /// indefinitely. A quarantined, ad-hoc-signed binary invoked that way is
    /// exactly what got one killed mid-run with SIGKILL "Code Signature
    /// Invalid" (see CloudSync-2026-09-15-190136.ips), which surfaced to the
    /// user as a baffling "no JSON result" error with nothing to act on.
    /// Safe to clear unconditionally: this binary already ships inside the
    /// app bundle we're running from.
    static func clearQuarantineIfNeeded(_ url: URL) {
        url.path.withCString { _ = removexattr($0, "com.apple.quarantine", 0) }
    }

    func binaryOrThrow() throws -> URL {
        guard let url = Self.locateBinary() else { throw CloudSyncClientError.helperMissing }
        return url
    }
}
