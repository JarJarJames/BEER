import Foundation

struct BottleLogEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let message: String
    let isError: Bool
}
