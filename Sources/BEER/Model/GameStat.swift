import Foundation

/// One fact shown at the top of a game's page.
struct GameStat: Equatable, Identifiable {
    /// The heading over the value in the Steam-style bar, e.g. "PLAY TIME".
    let title: String
    /// The value under that heading, e.g. "43.4 hours".
    let value: String
    /// The whole fact on one line, for the overlay, e.g. "Last played Today".
    let inline: String
    let systemImage: String

    var id: String { title }
}
