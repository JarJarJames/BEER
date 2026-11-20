import SwiftUI

/// Shown where a game needs a runtime and none is installed: downloads the
/// recommended GPTK right there, so nobody has to find the Runtimes tab.
/// Falls back to opening that tab when the catalog couldn't load.
struct InstallRuntimeButton: View {
    @Environment(ToolchainDetector.self) private var detector
    @Environment(RuntimeInstaller.self) private var runtimeInstaller

    var body: some View {
        if runtimeInstaller.isInstalling {
            RuntimeInstallProgress()
        } else if let release = runtimeInstaller.latestGPTK {
            Button {
                Task {
                    await runtimeInstaller.install(release)
                    await detector.refresh()
                }
            } label: {
                Label(RuntimeStrings.downloadRuntime(size: release.displaySize), systemImage: "arrow.down.circle")
            }
        } else {
            OpenRuntimesButton()
        }
    }
}
