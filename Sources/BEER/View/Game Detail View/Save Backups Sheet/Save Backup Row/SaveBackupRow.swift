import SwiftUI

struct SaveBackupRow: View {
    let snapshot: CloudSaveSnapshot
    /// The backup the current saves were restored from, still waiting on a
    /// choice against Steam Cloud.
    let isPendingSource: Bool
    let restoreDisabled: Bool
    let onRestore: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    if isPendingSource {
                        Text("Restored")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(SaveRestoreStrings.trigger(snapshot.label)) · \(SaveRestoreStrings.fileSummary(count: snapshot.fileCount, bytes: snapshot.byteCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(SaveRestoreStrings.revealButton, action: onReveal)
                .controlSize(.small)
            Button(SaveRestoreStrings.restoreButton, action: onRestore)
                .controlSize(.small)
                .disabled(restoreDisabled)
        }
        .padding(.vertical, 4)
    }
}
