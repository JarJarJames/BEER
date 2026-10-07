import SwiftUI

struct DLCPlaceholderView: View {
    let icon: String
    let tint: Color
    let text: String
    let onRetry: () -> Void

    var body: some View {
        CenteredContentView {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Check again", action: onRetry)
        }
    }
}
