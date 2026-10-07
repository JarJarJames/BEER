import Foundation

/// Backs the per-bottle environment-variable editor. The list is edited as an
/// ordered array rather than straight from the bottle's dictionary: a
/// dictionary reorders as you type, which makes the rows jump under the cursor.
@MainActor
final class EnvironmentEditorViewModel: ObservableObject {
    @Published var envVars: [EnvironmentVariable] = []
    private var loadedFor: UUID?

    /// Seed once per bottle. Re-seeding on every redraw would fight the user's
    /// cursor.
    func seed(from bottle: Bottle, id bottleID: UUID) {
        guard loadedFor != bottleID else { return }
        loadedFor = bottleID
        envVars = bottle.environmentOverrides
            .sorted { $0.key < $1.key }
            .map { EnvironmentVariable(key: $0.key, value: $0.value) }
    }

    func apply(_ preset: EnvironmentPreset) {
        if let existing = envVars.firstIndex(where: { $0.key == preset.key }) {
            envVars[existing].value = preset.value
        } else {
            envVars.append(EnvironmentVariable(key: preset.key, value: preset.value))
        }
    }

    func commit(to bottles: BottleStore, bottleID: UUID) {
        var overrides: [String: String] = [:]
        for entry in envVars {
            let key = entry.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            overrides[key] = entry.value
        }
        // Seeding the editor also fires onChange; writing only on a real
        // difference keeps that from scheduling a pointless save on every
        // appearance.
        let current = bottles.bottles.first { $0.id == bottleID }?.environmentOverrides ?? [:]
        guard overrides != current else { return }
        bottles.scheduleMutation(bottleID: bottleID) { $0.environmentOverrides = overrides }
    }
}
