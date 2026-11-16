import SwiftUI

struct RuntimeReleaseRow: View {
    let release: RuntimeRelease
    var recommended = false
    @EnvironmentObject private var detector: ToolchainDetector
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller

    var body: some View {
        let installed = runtimeInstaller.isInstalled(release)
        let busy = runtimeInstaller.installingTag == release.tag
        let runnable = runtimeInstaller.canRun(release)
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(release.tag).font(.callout.weight(.medium))
                Text("\(release.assetName) · \(release.displaySize)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if recommended {
                RecommendedRuntimeBadge()
            }
            if busy {
                RuntimeInstallProgress()
            } else if installed {
                Label(RuntimeManagerStrings.installed, systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if !runnable, let minimumMacOS = release.minimumMacOS {
                Text(RuntimeManagerStrings.needsMacOS(minimumMacOS))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await runtimeInstaller.install(release); await detector.refresh() }
                } label: {
                    Label(RuntimeManagerStrings.download, systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .disabled(runtimeInstaller.isInstalling)
            }
        }
        .padding(.vertical, 8)
        .opacity(runnable ? 1 : RuntimeManagerLayout.unavailableOpacity)
    }
}
