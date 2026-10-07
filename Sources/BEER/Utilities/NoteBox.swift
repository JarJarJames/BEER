import Foundation

/// Non-JSON lines a helper invocation printed (its stderr notes), kept so a
/// `runOnce` that never got a JSON result can report why instead of just
/// "no JSON result". Bounded like `BatchCollector.addNote` for the same reason.
final class NoteBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _notes: [String] = []

    func add(_ note: String) {
        lock.lock(); defer { lock.unlock() }
        if _notes.count < 200 { _notes.append(note) }
    }

    var all: [String] { lock.lock(); defer { lock.unlock() }; return _notes }
}
