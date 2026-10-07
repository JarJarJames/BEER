import Foundation
import SwiftUI

/// Lock-guarded drop box between the helper's output handler (off the main
/// actor) and the store (on it).
final class PresenceInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var _persona: PersonaUpdate?
    private var _error: String?
    private var _playtime: PlaytimeReport?

    func accept(_ obj: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        if let name = obj["persona_name"] as? String {
            _persona = PersonaUpdate(
                name: name,
                state: (obj["persona_state"] as? String) ?? "Online",
                avatarHash: obj["avatar_hash"] as? String,
                appID: (obj["presence_appid"] as? NSNumber)?.intValue ?? 0
            )
        }
        if let stopped = (obj["stopped"] as? NSNumber)?.intValue {
            _playtime = PlaytimeReport(
                appID: stopped,
                minutes: (obj["playtime_forever"] as? NSNumber)?.intValue ?? -1
            )
        }
        if let err = obj["error"] as? String { _error = err }
    }

    var playtime: PlaytimeReport? { lock.lock(); defer { lock.unlock() }; return _playtime }
    func clearPlaytime() { lock.lock(); _playtime = nil; lock.unlock() }

    func takePersona() -> PersonaUpdate? {
        lock.lock(); defer { lock.unlock() }
        defer { _persona = nil }
        return _persona
    }

    func takeError() -> String? {
        lock.lock(); defer { lock.unlock() }
        defer { _error = nil }
        return _error
    }
}
