import Foundation

// GPTK's Wine is built for Intel only, so every Apple Silicon Mac runs it
// through Rosetta. macOS doesn't ship Rosetta: it offers to install it the
// first time someone opens an Intel app from Finder, but not when another app
// starts one with `Process`. That fails with "Bad CPU type in executable"
// instead, so a Mac that has never opened an Intel app can't run Wine until
// BEER installs Rosetta itself.
enum RosettaInstaller {
    /// Present once Rosetta is installed.
    static let runtimePath = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: runtimePath)
    }

    /// Install Rosetta behind macOS's administrator password prompt. Returns
    /// false if the user cancels that prompt.
    static func install() async throws -> Bool {
        // `softwareupdate` needs root, and `with administrator privileges` is
        // how an app asks for it. The script is a fixed string: nothing from
        // the user or the network goes into it.
        let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
        let result = try await ShellRunner.run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", script],
            environment: [:],
            outputHandler: { _ in }
        )
        if result.exitCode != 0 {
            // -128 is AppleScript's "User canceled."
            if result.output.contains("-128") { return false }
            throw RosettaInstallError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard isInstalled() else {
            throw RosettaInstallError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return true
    }
}
