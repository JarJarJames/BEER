import XCTest
@testable import BEER

/// Regression for #65: Offline is account-wide, so sending it signed the
/// user's Steam client on every device out of Friends each time BEER opened.
final class SteamPersonaStateTests: XCTestCase {
    func testStatusMenuDoesNotOfferOffline() {
        XCTAssertFalse(SteamPersonaState.choices.contains(.offline))
        XCTAssertEqual(SteamPersonaState.choices, [.online, .away, .invisible])
    }

    func testOfflineIsSentAsInvisible() {
        XCTAssertEqual(SteamPersonaState.offline.assertable, .invisible)
        for state in SteamPersonaState.choices {
            XCTAssertEqual(state.assertable, state)
        }
    }

    func testSavedOfflineLoadsAsInvisible() {
        let saved = Data(#"{"desiredState":"Offline"}"#.utf8)
        XCTAssertEqual(SteamPresenceStore.storedState(from: saved), .invisible)
    }

    func testSavedStatusOtherwiseLoadsAsIs() {
        let saved = Data(#"{"desiredState":"Away"}"#.utf8)
        XCTAssertEqual(SteamPresenceStore.storedState(from: saved), .away)
    }
}
