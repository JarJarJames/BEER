import SwiftUI

struct CenteredContentView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }
}
