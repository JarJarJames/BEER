import Foundation

/// The moves under way, kept on disk (`game-moves.json`) so the next launch
/// knows what a crash or a pulled drive interrupted.
struct GameMoveJournal: Sendable {
    let url: URL

    func records() -> [GameMoveRecord] {
        // No file means no move was cut short.
        guard let data = try? Data(contentsOf: url) else { return [] }
        return attempt("Read game move journal", log: Log.install) {
            try JSONDecoder.gamenative.decode([GameMoveRecord].self, from: data)
        } ?? []
    }

    func record(for bottleID: UUID) -> GameMoveRecord? {
        records().first { $0.bottleID == bottleID }
    }

    /// Adds `record`, or replaces the one for the same bottle.
    func save(_ record: GameMoveRecord) {
        write(records().filter { $0.bottleID != record.bottleID } + [record])
    }

    func remove(bottleID: UUID) {
        write(records().filter { $0.bottleID != bottleID })
    }

    private func write(_ records: [GameMoveRecord]) {
        attempt("Write game move journal", log: Log.install) {
            if records.isEmpty {
                try FileManager.default.removeItemIfPresent(at: url)
                return
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.gamenative.encode(records).write(to: url, options: .atomic)
        }
    }
}
