import SwiftUI

struct RuntimeSection<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
