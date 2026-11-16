import SwiftUI

/// Stands in for the Play button while a launch is under way: which step it's
/// on, and, once the game has been slow to show a window, where to look.
struct LaunchStatusView: View {
    let phase: LaunchPhase
    let onShowLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LaunchStatusLayout.spacing) {
            HStack(spacing: LaunchStatusLayout.spacing) {
                if phase == .playing {
                    Image(systemName: phase.symbol)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(phase.title)
                    .font(.title3.bold())
            }
            .frame(minWidth: LaunchStatusLayout.minWidth, minHeight: LaunchStatusLayout.minHeight)
            .padding(.horizontal, LaunchStatusLayout.horizontalPadding)
            .background(
                Color.accentColor.opacity(LaunchStatusLayout.backgroundOpacity),
                in: RoundedRectangle(cornerRadius: LaunchStatusLayout.cornerRadius)
            )

            if phase == .startingGame(isSlow: true) {
                LaunchNote(text: LaunchStatusStrings.slowHint, isError: false, onShowLog: onShowLog)
            }
        }
    }
}
