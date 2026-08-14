import SwiftUI

struct DownloadsPane: View {
    @EnvironmentObject private var downloads: DownloadsStore
    @EnvironmentObject private var depotCtl: DepotDownloaderController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Downloads").font(.largeTitle.bold())

                if !depotCtl.isBusy && downloads.entries.isEmpty {
                    emptyView
                } else {
                    if !downloads.active.isEmpty {
                        sectionHeader("Active")
                        VStack(spacing: 10) {
                            ForEach(downloads.active) { entry in
                                DownloadRow(entry: entry)
                            }
                        }
                    }
                    if !downloads.recent.isEmpty {
                        sectionHeader("Recent")
                        VStack(spacing: 10) {
                            ForEach(downloads.recent) { entry in
                                DownloadRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No downloads yet").font(.headline)
            Text("Pick a game from your Library and click Install to start a download.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

private struct DownloadRow: View {
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
                        Text("\(byteString(d)) / \(byteString(t))")
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

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Download detail

