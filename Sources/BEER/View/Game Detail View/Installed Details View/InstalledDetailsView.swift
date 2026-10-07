import SwiftUI

struct InstalledDetailsView: View {
    let bottle: Bottle
    @ObservedObject var model: GameDetailViewModel
    @State private var isAdvancedExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Game Settings").font(.headline)
            RuntimeRow(bottle: bottle)
            GraphicsRow(bottle: bottle)
            DisplayModeRow(bottle: bottle)
            ControllerFixRow(bottle: bottle)
            LaunchArgumentsRow(bottle: bottle)
            SteamEmulatorRow(bottle: bottle, model: model)
            DLCRow(bottle: bottle, model: model)
            SteamCloudRow(bottle: bottle, model: model)

            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                AdvancedSettingsView(bottle: bottle)
                    .padding(.top, 10)
            } label: {
                Label("Advanced", systemImage: "gearshape.2")
                    .font(.headline)
            }
            .padding(.top, 6)

            Text("Changing the runtime swaps the Wine build this game runs on. Install additional Wine or GPTK versions from Runtime Manager in the sidebar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
