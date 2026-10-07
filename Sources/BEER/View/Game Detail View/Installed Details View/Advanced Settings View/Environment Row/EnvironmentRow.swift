import SwiftUI

/// Per-bottle environment variables, applied to the game's Wine process.
///
/// This is the escape hatch for the long tail of per-game breakage that no
/// amount of default-picking solves — a game needing a different graphics
/// backend, a DLL override, a debug toggle. Without it the only fix is
/// hand-editing `bottles.json`, which is not a fix a user can be asked to
/// perform.
struct EnvironmentRow: View {
    let bottleID: UUID
    let bottle: Bottle
    @EnvironmentObject private var bottles: BottleStore
    @StateObject private var editor = EnvironmentEditorViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(title: "Environment", alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach($editor.envVars) { $entry in
                        HStack(spacing: 6) {
                            TextField("NAME", text: $entry.key)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 190)
                            Text("=")
                                .foregroundStyle(.secondary)
                            TextField("value", text: $entry.value)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 240)
                            Button {
                                editor.envVars.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this variable")

                            if EnvironmentVariable.isOverriddenByBEER(entry.key) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help("BEER sets \(entry.key.trimmingCharacters(in: .whitespaces).uppercased()) itself, so this value is ignored at launch.")
                            }
                        }
                    }

                    HStack(spacing: 14) {
                        Button {
                            editor.envVars.append(EnvironmentVariable(key: "", value: ""))
                        } label: {
                            Label("Add Variable", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)

                        Menu {
                            ForEach(EnvironmentPreset.all) { preset in
                                Button {
                                    editor.apply(preset)
                                } label: {
                                    Text("\(preset.title) — \(preset.key)=\(preset.value)")
                                }
                                .help(preset.detail)
                            }
                        } label: {
                            Label("Known Fixes", systemImage: "wrench.and.screwdriver")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                Spacer()
            }

            Text("Set on the game's Wine process at launch. `WINEDLLOVERRIDES` is merged with the overrides BEER sets itself rather than replacing them. Changes apply next launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: bottleID) {
            editor.seed(from: bottle, id: bottleID)
        }
        .onChange(of: editor.envVars) { _, _ in
            editor.commit(to: bottles, bottleID: bottleID)
        }
    }
}
