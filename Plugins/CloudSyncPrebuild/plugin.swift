import PackagePlugin
import Foundation

/// Keeps the dev-installed CloudSync helper in sync with its C# sources
/// automatically, so a normal `swift build`/`swift run` always has an
/// up-to-date helper without anyone remembering to run
/// scripts/build_cloudsync.sh by hand.
///
/// This must be a `.buildCommand` (not `.prebuildCommand`): SwiftPM/llbuild
/// only re-invokes a `.prebuildCommand` when the target's *set* of source
/// files changes (a file added/removed), not when an existing file's
/// contents change — which is exactly the case every time someone edits
/// Program.cs. Declaring explicit `inputFiles` on a `.buildCommand` gets
/// correct, ordinary incremental tracking: llbuild reruns it exactly when
/// one of those files' contents/mtimes change.
@main
struct CloudSyncPrebuild: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let toolsDir = context.package.directory.appending(subpath: "Tools/CloudSync")
        let script = context.package.directory.appending(subpath: "scripts/cloudsync_prebuild.sh")
        let outputDir = context.pluginWorkDirectory.appending(subpath: "CloudSyncPrebuildOutput")
        let binary = outputDir.appending(subpath: "publish/CloudSync")

        var inputFiles: [Path] = [script]
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
                arguments: [script.string, outputDir.string],
                environment: ProcessInfo.processInfo.environment,
                inputFiles: inputFiles,
                outputFiles: [binary]
            )
        ]
    }
}
