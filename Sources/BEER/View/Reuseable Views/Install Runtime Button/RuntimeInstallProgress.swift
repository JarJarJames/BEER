import SwiftUI

/// How far a runtime install has got: a bar with the megabytes while it
/// downloads, then a spinner with the step (verifying, extracting).
struct RuntimeInstallProgress: View {
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller

    var body: some View {
        if let progress = runtimeInstaller.downloadProgress {
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                Text(RuntimeStrings.downloaded(progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: RuntimeInstallLayout.progressWidth)
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(runtimeInstaller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
