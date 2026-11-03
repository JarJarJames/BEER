import SwiftUI

/// A quiet note above the library: a drive holds games that aren't in BEER.
struct FoundGamesBanner: View {
    let driveName: String
    let count: Int
    let onReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.plus")
            Text(FoundGamesStrings.banner(count: count, drive: driveName))
            Spacer()
            Button(FoundGamesStrings.review, action: onReview)
            Button(FoundGamesStrings.dismiss, action: onDismiss)
        }
        .padding(FoundGamesLayout.bannerPadding)
        .background(Color.accentColor.opacity(FoundGamesLayout.bannerOpacity),
                    in: RoundedRectangle(cornerRadius: FoundGamesLayout.cornerRadius))
    }
}
