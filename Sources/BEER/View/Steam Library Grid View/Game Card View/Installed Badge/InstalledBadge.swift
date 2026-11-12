import SwiftUI

/// A library card's corner badge: "INSTALLED", "UPDATE", a drive warning, a
/// download's progress, or "NOT INSTALLED" for one that never finished. See
/// `LibraryCardBadge`.
///
/// It watches the downloads itself, so a progress tick redraws the few badges
/// on screen rather than the whole library grid.
struct InstalledBadge: View {
    let appID: Int
    let isInstalled: Bool
    /// False while the game's download hasn't finished.
    let isComplete: Bool
    let isDriveMissing: Bool
    let hasUpdate: Bool

    @EnvironmentObject private var downloads: DownloadsStore

    var body: some View {
        if let badge = LibraryCardBadge.resolve(
            isInstalled: isInstalled, isComplete: isComplete, isDriveMissing: isDriveMissing,
            hasUpdate: hasUpdate, download: downloads.entry(for: appID)
        ) {
            // The words where they fit; on a narrow card, a symbol and the
            // percent, so it never runs into the favorite star.
            ViewThatFits(in: .horizontal) {
                capsule(Text(badge.text), for: badge)
                if let symbol = badge.compactSymbol {
                    capsule(compactLabel(symbol, fraction: badge.fraction), for: badge)
                }
            }
            .help(badge.text)
        }
    }

    private func capsule(_ label: Text, for badge: LibraryCardBadge) -> some View {
        label
            .font(.caption2.weight(.heavy).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(LibraryGridLayout.badgeMinimumScale)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background { background(for: badge) }
            .foregroundStyle(.white)
    }

    private func compactLabel(_ symbol: String, fraction: Double?) -> Text {
        guard let fraction else { return Text(Image(systemName: symbol)) }
        return Text("\(Image(systemName: symbol)) \(fraction.percentString)")
    }

    /// Solid, or for a download a dark track filled as far as it's got.
    @ViewBuilder private func background(for badge: LibraryCardBadge) -> some View {
        if let fraction = badge.fraction {
            Color.black.opacity(LibraryGridLayout.badgeTrackOpacity)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        color(for: badge).opacity(0.85)
                            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    }
                }
                .clipShape(Capsule())
        } else {
            Capsule().fill(color(for: badge).opacity(0.85))
        }
    }

    private func color(for badge: LibraryCardBadge) -> Color {
        switch badge {
        case .installed: return .green
        case .update, .downloading: return .blue
        case .driveMissing, .paused: return .orange
        case .notInstalled: return .red
        }
    }
}
