import SwiftUI

/// Names a group of rows inside a runtime section.
struct RuntimeGroupHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, RuntimeManagerLayout.groupHeaderTopPadding)
    }
}
