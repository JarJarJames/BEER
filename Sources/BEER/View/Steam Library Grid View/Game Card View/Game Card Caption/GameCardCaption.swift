import SwiftUI

/// A game's name with the chosen caption under it.
struct GameCardCaption: View {
    let name: String
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.callout.bold())
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
