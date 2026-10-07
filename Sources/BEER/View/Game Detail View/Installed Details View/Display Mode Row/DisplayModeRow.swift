import SwiftUI

struct DisplayModeRow: View {
    let bottle: Bottle
    @EnvironmentObject private var bottles: BottleStore

    var body: some View {
        let bottleID = bottle.id
        let liveBottle = bottles.bottles.first(where: { $0.id == bottleID }) ?? bottle
        let resolutionMode = liveBottle.effectiveDisplayResolutionMode

        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(title: "Resolution") {

                Picker("Resolution", selection: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.effectiveDisplayResolutionMode ?? resolutionMode
                    },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.displayResolutionMode = newValue }
                    }
                )) {
                    ForEach(DisplayResolutionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
                .frame(width: 240, alignment: .leading)

                Spacer()
            }

            Text(resolutionMode == .highResolution
                ? "Exposes Retina resolutions to the game (up to twice the width and height) and treats it as DPI-aware. Sharper, but substantially more demanding; some games may not handle high-DPI mode correctly."
                : "Uses macOS point dimensions for better performance and compatibility. On Retina displays this limits games to half the high-resolution width and height.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
