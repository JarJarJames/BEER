import SwiftUI

/// Shown in place of Play when the Wine a game's bottle ran on is gone:
/// switches it to the runtime new games get, or downloads one when none is
/// installed.
struct MissingRuntimeNotice: View {
    let bottle: Bottle
    @EnvironmentObject private var bottles: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector

    var body: some View {
        Text(RuntimeStrings.runtimeMissing(bottle.runtimeLabel))
            .font(.caption)
            .foregroundStyle(.orange)
        if let runtime = detector.preferredGameRuntime {
            Button {
                bottles.scheduleMutation(bottleID: bottle.id) { $0.useRuntime(runtime) }
            } label: {
                Label(RuntimeStrings.useRuntime(runtime.displayName), systemImage: "arrow.triangle.2.circlepath")
            }
        } else {
            InstallRuntimeButton()
        }
    }
}
