import Foundation

/// An owned DLC whose files come down with the game itself: its depots are
/// listed in the game's own app info, so `DepotDownloader -app <game>` fetches
/// them (Fallout 4's HD texture pack, say). The install sheet lets the user
/// leave it out.
struct InstallableDLC: Codable, Hashable, Identifiable {
    var id: Int { appID }
    let appID: Int
    let name: String
    /// Nil when Steam lists no size.
    let bytes: Int64?
    let depotIDs: [Int]
}
