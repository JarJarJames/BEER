import SwiftUI

struct DLCManagerRow: View {
    let dlc: CloudSyncClient.DLCInfo
    let installed: Bool
    @ObservedObject var model: DLCManagerViewModel

    var body: some View {
        let active = model.activeDownload(for: dlc)

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dlc.name).font(.callout.weight(.medium))
                HStack(spacing: 8) {
                    Text("appID \(dlc.appID)")
                    if !dlc.hasDepots {
                        Text("No files to download")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let active {
                    ProgressView(value: active.fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 260)
                    Text(active.phaseText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if active != nil {
                ProgressView().controlSize(.small)
            } else if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Menu {
                    Button("Reinstall") { model.install(dlc) }
                    Button("Disable", role: .destructive) { model.disable(dlc) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.isBusy)
            } else {
                Button(dlc.hasDepots ? "Install" : "Enable") { model.install(dlc) }
                    .controlSize(.small)
                    .disabled(model.isBusy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
