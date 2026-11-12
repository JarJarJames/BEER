import SwiftUI

struct DownloadsPane: View {
    @EnvironmentObject private var downloads: DownloadsStore
    @EnvironmentObject private var depotCtl: DepotDownloaderController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Downloads").font(.largeTitle.bold())

                if !depotCtl.isBusy && downloads.entries.isEmpty {
                    emptyView
                } else {
                    if !downloads.inProgress.isEmpty {
                        sectionHeader("Active")
                        VStack(spacing: 10) {
                            ForEach(downloads.inProgress) { entry in
                                DownloadRow(
                                    entry: entry,
                                    onPause: depotCtl.pausableIDs.contains(entry.id)
                                        ? { depotCtl.pause(entry.id, in: downloads) } : nil,
                                    onResume: entry.isPaused ? { resume(entry) } : nil
                                )
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

    /// On the game's page, which can ask to reconnect Steam or report a full
    /// disk; this list can't.
    private func resume(_ entry: DownloadsStore.Entry) {
        dismiss()
        GameLinkRouter.shared.resume(entry)
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
