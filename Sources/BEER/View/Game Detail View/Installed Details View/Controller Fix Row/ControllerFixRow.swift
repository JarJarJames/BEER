import SwiftUI

/// Opt-in per game. A Steam Controller reaches Wine through Steam's virtual
/// HID gamepad, whose report Wine mangles — the D-pad disappears and buttons
/// land on the wrong actions. The fix corrects that, but it rewrites what the
/// game reads from the HID device, so it stays off unless a game needs it.
///
/// Named for the Steam Controller because that is the only pad it has been
/// verified against; the underlying fault is not necessarily exclusive to it.
struct ControllerFixRow: View {
    let bottle: Bottle
    @EnvironmentObject private var bottles: BottleStore

    var body: some View {
        let bottleID = bottle.id
        let installed = ControllerSupport.fixIsInstalled

        VStack(alignment: .leading, spacing: 4) {
            SettingsRow(title: "Steam Controller Fix") {
                Toggle("Steam Controller fix", isOn: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.effectiveControllerFix
                            ?? bottle.effectiveControllerFix
                    },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.controllerFix = newValue }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!installed)

                Text(installed
                     ? "Turn on if the D-pad or buttons misbehave."
                     : "Run Tools/ControllerFix/build.sh to enable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }
}
