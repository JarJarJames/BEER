import SwiftUI

/// Downloads in the top bar: a ring and percent while something downloads,
/// opening the list of active and recent downloads.
///
/// A plain button that brightens on hover, rather than the toolbar's own
/// highlight box, which was wider than the icon and looked out of place.
struct DownloadsToolbarButton: View {
    @EnvironmentObject private var downloads: DownloadsStore
    @State private var isShowingList = false
    @State private var isHovering = false

    var body: some View {
        Button { isShowingList.toggle() } label: {
            label
                .foregroundStyle(isHovering || isShowingList ? .primary : .secondary)
                .padding(.horizontal, MainShellLayout.toolbarButtonPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(DownloadsStrings.title)
        .accessibilityLabel(DownloadsStrings.title)
        .popover(isPresented: $isShowingList, arrowEdge: .bottom) {
            DownloadsPane()
                .frame(width: MainShellLayout.downloadsPopoverSize.width,
                       height: MainShellLayout.downloadsPopoverSize.height)
        }
    }

    @ViewBuilder private var label: some View {
        if let fraction = downloads.overallFraction {
            HStack(spacing: 5) {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
            }
            // Fixed while downloading: the percent changes many times a
            // second, and a toolbar item resizing with it can loop layout.
            .frame(width: MainShellLayout.downloadsButtonWidth)
        } else {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: MainShellLayout.toolbarIconSize))
        }
    }
}
