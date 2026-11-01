import SwiftUI

struct SteamClientLoaderRow: View {
    let bottle: Bottle
    @EnvironmentObject private var bottles: BottleStore

    var body: some View {
        let bottleID = bottle.id
        let liveBottle = bottles.live(bottle)

        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(title: SteamClientLoaderStrings.title) {
                Picker(SteamClientLoaderStrings.title, selection: Binding(
                    get: { bottles.live(bottle).effectiveSteamClientLoaderMode },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.steamClientLoaderMode = newValue }
                    }
                )) {
                    ForEach(SteamClientLoaderMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()

                Spacer()
            }
            caption(SteamClientLoaderStrings.modeCaption)

            if liveBottle.effectiveSteamClientLoaderMode != .off {
                toggleRow(
                    title: SteamClientLoaderStrings.overlayTitle,
                    label: SteamClientLoaderStrings.overlayToggle,
                    isOn: Binding(
                        get: { bottles.live(bottle).effectiveSteamClientLoaderInjectsOverlay },
                        set: { newValue in
                            bottles.scheduleMutation(bottleID: bottleID) { $0.steamClientLoaderInjectsOverlay = newValue }
                        }
                    )
                )
                caption(SteamClientLoaderStrings.overlayCaption)

                toggleRow(
                    title: SteamClientLoaderStrings.staysOpenTitle,
                    label: SteamClientLoaderStrings.staysOpenToggle,
                    isOn: Binding(
                        get: { bottles.live(bottle).effectiveSteamClientLoaderStaysOpen },
                        set: { newValue in
                            bottles.scheduleMutation(bottleID: bottleID) { $0.steamClientLoaderStaysOpen = newValue }
                        }
                    )
                )
                caption(SteamClientLoaderStrings.staysOpenCaption)
            }
        }
    }

    private func toggleRow(title: String, label: String, isOn: Binding<Bool>) -> some View {
        SettingsRow(title: title) {
            Toggle(label, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            Spacer()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, SettingsRow<EmptyView>.captionIndent)
            .fixedSize(horizontal: false, vertical: true)
    }
}
