import SwiftUI

struct LaunchArgumentsRow: View {
    let bottle: Bottle
    @EnvironmentObject private var bottles: BottleStore

    var body: some View {
        let bottleID = bottle.id

        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(title: "Launch arguments") {

                TextField("Optional game arguments", text: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.effectiveGameLaunchArguments
                            ?? bottle.effectiveGameLaunchArguments
                    },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.gameLaunchArguments = newValue }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)

                Spacer()
            }

            Text("Passed directly to the game executable. For Unity games, for example: -screen-width 3024 -screen-height 1964 -screen-fullscreen 0")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
