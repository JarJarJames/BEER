import SwiftUI

// The game's save backups, newest first, with a way to put one back. Every
// restore is confirmed with exactly what it replaces, and backs up the
// current saves before touching them.

struct SaveBackupsSheet: View {
    let bottle: Bottle
    @ObservedObject var model: GameDetailViewModel

    var body: some View {
        let busy = model.savesAreBusy(bottle)

        VStack(alignment: .leading, spacing: 14) {
            Text(SaveRestoreStrings.sheetTitle)
                .font(.title2.bold())
            Text(SaveRestoreStrings.sheetCaption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = model.saveBackupsError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.saveBackups.isEmpty {
                Text(SaveRestoreStrings.emptyList)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: SaveRestoreLayout.emptyListHeight)
            } else {
                List(model.saveBackups) { snapshot in
                    SaveBackupRow(
                        snapshot: snapshot,
                        isPendingSource: model.pendingRestore?.snapshotName == snapshot.id,
                        restoreDisabled: busy,
                        onRestore: { model.prepareRestore(snapshot, bottle: bottle) },
                        onReveal: { model.revealBackup(snapshot) }
                    )
                }
                .frame(minHeight: SaveRestoreLayout.listMinHeight)
            }

            HStack {
                if busy {
                    Text(SaveRestoreStrings.busy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(SaveRestoreStrings.doneButton) { model.isShowingSaveBackups = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: SaveRestoreLayout.sheetWidth)
        .confirmationDialog(
            model.restorePlanToConfirm.map { SaveRestoreStrings.confirmTitle($0.snapshot.date) } ?? "",
            isPresented: Binding(get: { model.restorePlanToConfirm != nil },
                                 set: { if !$0 { model.restorePlanToConfirm = nil } }),
            presenting: model.restorePlanToConfirm
        ) { plan in
            Button(SaveRestoreStrings.confirmButton, role: .destructive) { model.restore(plan, bottle: bottle) }
            Button("Cancel", role: .cancel) { model.restorePlanToConfirm = nil }
        } message: { plan in
            Text(SaveRestoreStrings.confirmMessage(plan))
        }
    }
}
