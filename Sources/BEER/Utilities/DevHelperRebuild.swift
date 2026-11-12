import Foundation

/// Finishes a CloudSync helper rebuild that `swift run` couldn't.
///
/// `swift build` rebuilds the helper in SwiftPM's plugin sandbox, which has no
/// network. When the helper needs a .NET package that isn't downloaded yet
/// (after a .NET SDK update, say) that rebuild fails, and the plugin falls back
/// to the installed helper with a `needs-rebuild` note beside it. BEER isn't
/// sandboxed, so at launch it runs the same script, which can download what it
/// needs. A shipped app has no plugin output, so this does nothing there.
enum DevHelperRebuild {
    static let markerName = "needs-rebuild"

    /// Rebuild before anything uses the helper, so the app never runs old
    /// helper code. Only when the plugin left the note; otherwise instant.
    static func runIfNeeded(in checkout: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) async {
        guard let plan = plan(in: checkout) else { return }
        print("CloudSync helper: the build sandbox couldn't rebuild it, so BEER is rebuilding it now…")
        Log.cloudSync.notice("Rebuilding the CloudSync helper outside the build sandbox")
        do {
            let result = try await ShellRunner.run(
                executable: "/bin/bash",
                arguments: [plan.script.path, plan.outputDirectory.path, plan.stamp.path],
                environment: [:],
                outputHandler: { _ in }
            )
            if result.exitCode == 0, !FileManager.default.fileExists(atPath: plan.marker.path) {
                print("CloudSync helper: rebuilt.")
                return
            }
            let tail = result.output.split(separator: "\n").suffix(8).joined(separator: "\n")
            print("CloudSync helper: rebuild failed; still using the older helper.\n\(tail)")
            Log.cloudSync.error("CloudSync helper rebuild failed: \(tail, privacy: .public)")
        } catch {
            print("CloudSync helper: couldn't run the rebuild: \(error.localizedDescription)")
            Log.cloudSync.error("Couldn't run the CloudSync helper rebuild: \(error.localizedDescription, privacy: .public)")
        }
    }

    struct Plan: Equatable {
        let script: URL
        let outputDirectory: URL
        let stamp: URL
        let marker: URL
    }

    /// What to run, when `checkout` is a source checkout whose plugin output
    /// has the note. The paths mirror `Plugins/CloudSyncPrebuild`.
    static func plan(in checkout: URL) -> Plan? {
        guard let binary = CloudSyncClient.locatePluginPublishedBinary(under: checkout) else { return nil }
        let publish = binary.deletingLastPathComponent()
        let marker = publish.appendingPathComponent(markerName)
        let script = checkout.appendingPathComponent("scripts/cloudsync_prebuild.sh")
        let fm = FileManager.default
        guard fm.fileExists(atPath: marker.path), fm.fileExists(atPath: script.path) else { return nil }
        let outputDirectory = publish.deletingLastPathComponent()
        return Plan(
            script: script,
            outputDirectory: outputDirectory,
            stamp: outputDirectory.deletingLastPathComponent().appendingPathComponent("last-run.stamp"),
            marker: marker
        )
    }
}
