import SwiftUI

struct DisplayModeRow: View {
    let bottle: Bottle
    @EnvironmentObject private var bottles: BottleStore

    var body: some View {
        let bottleID = bottle.id
        let liveBottle = bottles.bottles.first(where: { $0.id == bottleID }) ?? bottle
        let resolutionMode = liveBottle.effectiveDisplayResolutionMode

        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(title: DisplayModeStrings.resolutionTitle) {

                Picker(DisplayModeStrings.resolutionTitle, selection: Binding(
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
                ? DisplayModeStrings.highResolutionCaption
                : DisplayModeStrings.standardCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                .fixedSize(horizontal: false, vertical: true)

            SettingsRow(title: DisplayModeStrings.captureTitle) {
                Toggle(DisplayModeStrings.captureToggle, isOn: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.effectiveCaptureDisplayInFullscreen
                            ?? bottle.effectiveCaptureDisplayInFullscreen
                    },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.captureDisplayInFullscreen = newValue }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

                Spacer()
            }

            Text(DisplayModeStrings.captureCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
