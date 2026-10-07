import Foundation

final class BatchCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _ops: [CloudSyncClient.BatchOp] = []
    private var _notes: [String] = []
    private var _fatal: String?
    private var _authFailed = false
    private var _rateLimited = false

    func add(_ op: CloudSyncClient.BatchOp) { lock.lock(); _ops.append(op); lock.unlock() }
    /// Bounded: a chatty helper shouldn't be able to grow this without limit.
    func addNote(_ note: String) {
        lock.lock(); defer { lock.unlock() }
        if _notes.count < 200 { _notes.append(note) }
    }
    func setFatal(_ msg: String, authFailed: Bool, rateLimited: Bool) {
        lock.lock(); _fatal = msg; _authFailed = authFailed; _rateLimited = rateLimited; lock.unlock()
    }

    var ops: [CloudSyncClient.BatchOp] { lock.lock(); defer { lock.unlock() }; return _ops }
    var notes: [String] { lock.lock(); defer { lock.unlock() }; return _notes }
    var count: Int { lock.lock(); defer { lock.unlock() }; return _ops.count }
    var fatal: String? { lock.lock(); defer { lock.unlock() }; return _fatal }
    var authFailed: Bool { lock.lock(); defer { lock.unlock() }; return _authFailed }
    var rateLimited: Bool { lock.lock(); defer { lock.unlock() }; return _rateLimited }
}
