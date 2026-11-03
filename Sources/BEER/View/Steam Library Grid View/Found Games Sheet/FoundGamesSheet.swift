import SwiftUI

/// The games found on one drive, each with a checkbox, to add back to BEER.
struct FoundGamesSheet: View {
    let driveName: String
    let games: [FoundGame]
    let isAdding: Bool
    let onAdd: ([FoundGame]) -> Void
    let onCancel: () -> Void
    @State private var selected: Set<String>

    init(driveName: String, games: [FoundGame], isAdding: Bool,
         onAdd: @escaping ([FoundGame]) -> Void, onCancel: @escaping () -> Void) {
        self.driveName = driveName
        self.games = games
        self.isAdding = isAdding
        self.onAdd = onAdd
        self.onCancel = onCancel
        _selected = State(initialValue: Set(games.filter(\.canAdd).map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(FoundGamesStrings.sheetTitle)
                .font(.title2.bold())
            Text(FoundGamesStrings.message(drive: driveName))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(games) { game in
                Toggle(isOn: Binding(
                    get: { selected.contains(game.id) },
                    set: { isOn in
                        if isOn { selected.insert(game.id) } else { selected.remove(game.id) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.marker.name)
                        Text(game.blockedReason ?? (game.marker.isNonSteam ? FoundGamesStrings.nonSteam : FoundGamesStrings.steam))
                            .font(.caption)
                            .foregroundStyle(game.canAdd ? Color.secondary : Color.orange)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!game.canAdd || isAdding)
            }
            .frame(height: FoundGamesLayout.listHeight)

            Text(FoundGamesStrings.verifyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if isAdding {
                    ProgressView().controlSize(.small)
                    Text(FoundGamesStrings.adding).foregroundStyle(.secondary)
                }
                Spacer()
                Button(FoundGamesStrings.cancelButton, role: .cancel, action: onCancel)
                    .disabled(isAdding)
                Button(FoundGamesStrings.addButton) {
                    onAdd(games.filter { selected.contains($0.id) })
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || isAdding)
            }
        }
        .padding(24)
        .frame(width: FoundGamesLayout.sheetWidth)
        .interactiveDismissDisabled(isAdding)
    }
}
