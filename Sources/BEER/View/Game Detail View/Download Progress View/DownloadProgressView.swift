import SwiftUI

struct DownloadProgressView: View {
    let entry: DownloadsStore.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.phaseText).font(.callout.bold())
                Spacer()
                Text(entry.fraction.percentString).font(.callout.monospacedDigit())
            }
            ProgressView(value: entry.fraction)
                .progressViewStyle(.linear)
            if let downloaded = entry.downloadedBytes, let total = entry.totalBytes, total > 0 {
                Text("\(downloaded.fileSizeString) / \(total.fileSizeString)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !entry.logTail.isEmpty {
                DisclosureGroup("DepotDownloader output") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(entry.logTail.enumerated()), id: \.0) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 160)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .font(.caption)
            }
        }
    }
}
