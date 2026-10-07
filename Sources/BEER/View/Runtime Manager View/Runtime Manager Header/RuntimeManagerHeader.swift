import SwiftUI

struct RuntimeManagerHeader: View {
    @EnvironmentObject private var detector: ToolchainDetector
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Runtime Manager")
                    .font(.largeTitle.bold())
                Text("Install and manage Wine and Game Porting Toolkit runtimes. Assign a runtime to a game from that game's settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Task {
                    await detector.refresh()
                    await runtimeInstaller.refresh()
                    await detector.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(detector.isRefreshing || runtimeInstaller.isRefreshing || runtimeInstaller.isInstalling)
        }
    }
}
