import SwiftUI

/// Marks the runtime new games get on this Mac.
struct RecommendedRuntimeBadge: View {
    var body: some View {
        Label(RuntimeManagerStrings.recommended, systemImage: "star.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.accentColor)
    }
}
