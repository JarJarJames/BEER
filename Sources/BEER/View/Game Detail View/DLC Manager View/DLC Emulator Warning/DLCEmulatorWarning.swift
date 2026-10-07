import SwiftUI

struct DLCEmulatorWarning: View {
    var body: some View {
        Label(
            "The Steam emulator isn't applied to this game yet. DLC will download, but the game can't see it until you apply the emulator from Game Settings.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }
}
