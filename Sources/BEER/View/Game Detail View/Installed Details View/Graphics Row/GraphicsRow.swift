import SwiftUI

struct GraphicsRow: View {
    let bottle: Bottle
    @EnvironmentObject private var bottles: BottleStore
    @EnvironmentObject private var graphicsTranslator: GraphicsTranslatorInstaller

    var body: some View {
        let bottleID = bottle.id
        SettingsRow(title: "Graphics") {
            Picker("Graphics", selection: Binding(
                get: { bottles.bottles.first(where: { $0.id == bottleID })?.effectiveGraphicsBackend ?? bottle.effectiveGraphicsBackend },
                set: { newValue in bottles.scheduleMutation(bottleID: bottleID) { $0.graphicsBackend = newValue } }
            )) {
                ForEach(bottle.availableGraphicsBackends) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            if graphicsTranslator.busy != nil {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
    }
}
