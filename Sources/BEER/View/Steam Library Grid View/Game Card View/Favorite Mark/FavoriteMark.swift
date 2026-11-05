import SwiftUI

/// The star on a favorite game's card.
struct FavoriteMark: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.yellow)
            .padding(5)
            .background(.black.opacity(0.55), in: Circle())
            .accessibilityLabel(GameOrganizeStrings.favoriteHelp)
    }
}
