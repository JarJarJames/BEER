import Foundation

/// Non-JSON lines a helper invocation printed (its stderr notes), kept so a
/// `runLocal` that never got a JSON result can report why instead of just
/// "no JSON result". Bounded, so a chatty helper can't grow it without limit.
final class NoteBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _notes: [String] = []

    func add(_ note: String) {
        lock.lock(); defer { lock.unlock() }
        if _notes.count < 200 { _notes.append(note) }
    }

    var all: [String] { lock.lock(); defer { lock.unlock() }; return _notes }
}
