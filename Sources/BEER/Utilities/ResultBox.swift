import Foundation

final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _auth: CloudSyncClient.AuthResult?
    private var _dict: [String: Any]?
    private var _error: String?
    private var _authFailed = false

    private var _rateLimited = false

    func set(_ a: CloudSyncClient.AuthResult) { lock.lock(); _auth = a; lock.unlock() }
    func setDict(_ d: [String: Any]) { lock.lock(); _dict = d; lock.unlock() }
    func setError(_ e: String, authFailed: Bool = false, rateLimited: Bool = false) {
        lock.lock(); _error = e; _authFailed = authFailed; _rateLimited = rateLimited; lock.unlock()
    }

    var auth: CloudSyncClient.AuthResult? { lock.lock(); defer { lock.unlock() }; return _auth }
    var dict: [String: Any]? { lock.lock(); defer { lock.unlock() }; return _dict }
    var error: String? { lock.lock(); defer { lock.unlock() }; return _error }
    var authFailed: Bool { lock.lock(); defer { lock.unlock() }; return _authFailed }
    var rateLimited: Bool { lock.lock(); defer { lock.unlock() }; return _rateLimited }
}
