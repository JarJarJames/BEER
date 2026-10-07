import Foundation

struct RuntimeEntrypoints: Codable, Hashable {
    var wine: String
    var wineboot: String?
    var wineserver: String?
}
