import SwiftUI

struct DownloadRow: View {
    let entry: DownloadsStore.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.name).font(.callout.bold())
                Spacer()
                Text(entry.phaseText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            if entry.isActive {
                ProgressView(value: entry.fraction).progressViewStyle(.linear)
                HStack {
                    Text(String(format: "%.0f%%", entry.fraction * 100))
                        .font(.caption.monospacedDigit())
                    Spacer()
                    if let d = entry.downloadedBytes, let t = entry.totalBytes, t > 0 {
                        Text("\(d.fileSizeString) / \(t.fileSizeString)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch entry.status {
        case .completed: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}
