import SwiftUI

struct DLCRow: View {
    let bottle: Bottle
    @ObservedObject var model: GameDetailViewModel

    var body: some View {
        if let state = model.dlcRowState(bottle: bottle) {
            SettingsRow(title: "DLC") {
                switch state {
                case .installed(let owned, let installed):
                    if installed >= owned {
                        Label("All \(owned) installed", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else {
                        Label("\(installed) of \(owned) installed", systemImage: "shippingbox.fill")
                            .foregroundStyle(installed == 0 ? .orange : .primary)
                            .font(.callout)
                    }
                    Spacer()
                    Button("Manage…") { model.isShowingDLCManager = true }
                        .controlSize(.small)

                case .loading:
                    ProgressView().controlSize(.small)
                    Text("Checking your Steam licences…")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                case .failed:
                    Label("Couldn't check for DLC", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Spacer()
                    Button("Retry") { model.reloadDLC() }
                        .controlSize(.small)

                case .unchecked:
                    Text("Not checked yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for DLC") { model.reloadDLC() }
                        .controlSize(.small)
                }
            }
        }
    }
}
