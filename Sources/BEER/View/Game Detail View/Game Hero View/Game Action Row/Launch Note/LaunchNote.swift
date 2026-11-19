import SwiftUI

/// A line under the Play button or status, with a way to the bottle's log:
/// the slow-start hint, or why the last launch stopped.
struct LaunchNote: View {
    let text: String
    let isError: Bool
    let onShowLog: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LaunchStatusLayout.spacing) {
            Text(text)
                .font(.caption)
                .foregroundStyle(isError ? Color.red : Color.white.opacity(0.78))
                .lineLimit(LaunchStatusLayout.noteLineLimit)
                .fixedSize(horizontal: false, vertical: true)
            Button(LaunchStatusStrings.showLog, action: onShowLog)
                .controlSize(.small)
                .help(LaunchStatusStrings.showLogHelp)
        }
        .frame(maxWidth: LaunchStatusLayout.noteMaxWidth, alignment: .leading)
    }
}
