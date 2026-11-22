import SwiftUI

struct RuntimeRow: View {
    let bottle: Bottle
    @Environment(BottleStore.self) private var bottles
    @Environment(ToolchainDetector.self) private var detector

    var body: some View {
        let bottleID = bottle.id
        SettingsRow(title: "Runtime") {

            if detector.candidates.isEmpty {
                Text(bottle.runtimeLabel).font(.callout)
            } else {
                Picker("Runtime", selection: Binding(
                    get: { bottles.bottles.first(where: { $0.id == bottleID })?.runtimeLocationPath ?? bottle.runtimeLocationPath },
                    set: { newID in
                        guard let runtime = detector.candidates.first(where: { $0.id == newID }) else { return }
                        bottles.scheduleMutation(bottleID: bottleID) { $0.useRuntime(runtime) }
                    }
                )) {
                    ForEach(detector.candidates) { rt in
                        Text(rt.displayName).tag(rt.id)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Spacer()
        }
    }
}
