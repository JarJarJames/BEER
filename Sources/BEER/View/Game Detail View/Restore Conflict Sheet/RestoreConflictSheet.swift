import SwiftUI

// Shown when a sync finds restored saves that differ from Steam Cloud's, like
// Steam's own Cloud Sync Conflict: both sides, and what each choice does,
// before anything is written.

struct RestoreConflictSheet: View {
    let prompt: RestoreConflictPrompt
    let onKeepRestored: () -> Void
    let onUseCloud: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let conflict = prompt.conflict

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(SaveRestoreStrings.conflictTitle, systemImage: "exclamationmark.icloud")
                    .font(.title2.bold())
                Text(SaveRestoreStrings.conflictIntro)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 12) {
                side(SaveRestoreStrings.localSide, systemImage: "laptopcomputer", lines: SaveRestoreStrings.localDetail(conflict))
                side(SaveRestoreStrings.cloudSide, systemImage: "icloud", lines: SaveRestoreStrings.cloudDetail(conflict))
            }

            choice(SaveRestoreStrings.keepRestoredButton,
                   consequence: SaveRestoreStrings.keepRestoredConsequence(conflict),
                   action: onKeepRestored)
            choice(SaveRestoreStrings.useCloudButton,
                   consequence: SaveRestoreStrings.useCloudConsequence,
                   action: onUseCloud)

            Divider()

            HStack {
                Text(isLaunch ? SaveRestoreStrings.cancelLaunchConsequence : SaveRestoreStrings.cancelSyncConsequence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(SaveRestoreStrings.cancelButton, action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: SaveRestoreLayout.sheetWidth)
        .interactiveDismissDisabled(true)
    }

    private var isLaunch: Bool {
        if case .launch = prompt.retry { return true }
        return false
    }

    private func side(_ title: String, systemImage: String, lines: [String]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { Text($0).font(.callout) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage).font(.headline)
        }
    }

    private func choice(_ title: String, consequence: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button(title, action: action)
                .frame(width: SaveRestoreLayout.choiceButtonWidth, alignment: .leading)
            Text(consequence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
