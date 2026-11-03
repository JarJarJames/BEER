import SwiftUI

struct InstalledDetailsView: View {
    let bottle: Bottle
    @ObservedObject var model: GameDetailViewModel
    @State private var isAdvancedExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let driveName = model.installLocation?.missingDriveName {
                Label(InstallDriveStrings.driveMissingDetail(driveName), systemImage: "externaldrive.badge.xmark")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Game Settings").font(.headline)
            InstallLocationRow(bottle: bottle, model: model)
            RuntimeRow(bottle: bottle)
            GraphicsRow(bottle: bottle)
            DisplayModeRow(bottle: bottle)
            LaunchArgumentsRow(bottle: bottle)
            if !model.game.effectiveIsNonSteam {
                SteamEmulatorRow(bottle: bottle, model: model)
                DLCRow(bottle: bottle, model: model)
                SteamCloudRow(bottle: bottle, model: model)
            }

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
