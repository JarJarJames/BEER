import Foundation

final class BatchCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _ops: [CloudSyncClient.BatchOp] = []
    private var _fatal: String?
    private var _authFailed = false
    private var _rateLimited = false

    func add(_ op: CloudSyncClient.BatchOp) { lock.lock(); _ops.append(op); lock.unlock() }
    func setFatal(_ msg: String, authFailed: Bool, rateLimited: Bool) {
        lock.lock(); _fatal = msg; _authFailed = authFailed; _rateLimited = rateLimited; lock.unlock()
    }

    var ops: [CloudSyncClient.BatchOp] { lock.lock(); defer { lock.unlock() }; return _ops }
    var count: Int { lock.lock(); defer { lock.unlock() }; return _ops.count }
    var fatal: String? { lock.lock(); defer { lock.unlock() }; return _fatal }
    var authFailed: Bool { lock.lock(); defer { lock.unlock() }; return _authFailed }
    var rateLimited: Bool { lock.lock(); defer { lock.unlock() }; return _rateLimited }
}
