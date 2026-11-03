import PackagePlugin
import Foundation

/// Rebuilds the CloudSync helper on every `swift build`/`swift run`, so the
/// app never runs with a helper that is stale or broken.
///
/// This used to rerun only when a `.cs`/`.csproj` file changed. That left a
/// helper broken any other way (a half-written publish, a file another tool
/// replaced) in place across every later build, and the app failed at runtime
/// with nothing telling you to rebuild it. So the command also takes a stamp
/// file as an input, and the script rewrites the stamp each run: the next
/// build always sees a changed input and runs it again. (A declared output
/// that's never written doesn't work: every output gets copied into the
/// resource bundle, and the copy fails.) `dotnet publish` skips the compile
/// when nothing changed, so the rerun costs seconds.
///
/// This must be a `.buildCommand` (not `.prebuildCommand`): a prebuild
/// command's outputs are treated as new sources for the target, and the
/// helper isn't one.
@main
struct CloudSyncPrebuild: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let toolsDir = context.package.directory.appending(subpath: "Tools/CloudSync")
        let script = context.package.directory.appending(subpath: "scripts/cloudsync_prebuild.sh")
        let outputDir = context.pluginWorkDirectory.appending(subpath: "CloudSyncPrebuildOutput")
        let binary = outputDir.appending(subpath: "publish/CloudSync")
        // Rewritten by every run (see above), so the next build runs it again.
        let stamp = context.pluginWorkDirectory.appending(subpath: "last-run.stamp")
        // An input has to exist before the first run.
        if !FileManager.default.fileExists(atPath: stamp.string) {
            FileManager.default.createFile(atPath: stamp.string, contents: Data())
        }

        var inputFiles: [Path] = [script, stamp]
        let relativePaths = (FileManager.default.enumerator(atPath: toolsDir.string)?.allObjects as? [String]) ?? []
        for relativePath in relativePaths {
            guard relativePath.hasSuffix(".cs") || relativePath.hasSuffix(".csproj") else { continue }
            if relativePath.hasPrefix("bin/") || relativePath.hasPrefix("obj/") || relativePath.hasPrefix("publish/") {
                continue
            }
            inputFiles.append(toolsDir.appending(subpath: relativePath))
        }

        return [
            .buildCommand(
                displayName: "Rebuild CloudSync helper",
                executable: Path("/bin/bash"),
                arguments: [script.string, outputDir.string, stamp.string],
                environment: ProcessInfo.processInfo.environment,
                inputFiles: inputFiles,
                outputFiles: [binary]
            )
        ]
    }
}
