import Foundation

/// One row in the per-bottle environment editor. Carries its own identity so
/// the list keeps its order while a key is being typed.
struct EnvironmentVariable: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String

    /// Variables `BottleStore.environment(for:prefix:)` assigns unconditionally.
    /// A user value for one of these never reaches the game, so the editor flags
    /// it rather than letting someone believe they changed something.
    ///
    /// `WINEDLLOVERRIDES` is deliberately absent: that one is merged with BEER's
    /// own overrides, so a user value does take effect.
    private static let beerManagedKeys: Set<String> = [
        "WINEPREFIX", "WINEARCH", "USER", "USERNAME", "PATH",
    ]

    static func isOverriddenByBEER(_ key: String) -> Bool {
        beerManagedKeys.contains(key.trimmingCharacters(in: .whitespaces).uppercased())
    }
}
