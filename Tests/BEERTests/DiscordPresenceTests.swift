import XCTest
@testable import BEER

final class DiscordPresenceTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Activity

    func testSteamGameShowsItsArtWithTheBEERBadge() {
        let game = SteamLibraryGame(appID: 379430, name: "Kingdom Come: Deliverance")
        let activity = DiscordActivity(game: game, startedAt: started)

        XCTAssertEqual(activity.name, "Kingdom Come: Deliverance with BEER")
        XCTAssertEqual(activity.timestamps.start, 1_700_000_000)
        XCTAssertEqual(activity.details, "Playing with BEER on Mac")
        XCTAssertEqual(activity.assets.largeImage, "https://cdn.akamai.steamstatic.com/steam/apps/379430/library_600x900.jpg")
        XCTAssertEqual(activity.assets.smallImage, DiscordPresenceConfig.logoAssetKey)
    }

    func testNonSteamGameFallsBackToTheLogo() {
        var game = SteamLibraryGame(appID: -1, name: "Some Mod Launcher")
        game.isNonSteam = true
        game.customImagePath = "/Users/someone/art.png"
        let activity = DiscordActivity(game: game, startedAt: started)

        XCTAssertEqual(activity.name, "Some Mod Launcher with BEER")
        XCTAssertEqual(activity.assets.largeImage, DiscordPresenceConfig.logoAssetKey)
        XCTAssertNil(activity.assets.smallImage)
    }

    // MARK: - Wire format

    func testSetActivityCommandMatchesDiscordsShape() throws {
        let game = SteamLibraryGame(appID: 620, name: "Portal 2")
        let activity = DiscordActivity(game: game, startedAt: started)
        let data = try DiscordPresence.setActivityCommand(activity, pid: 42, nonce: "n")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["cmd"] as? String, "SET_ACTIVITY")
        XCTAssertEqual(json["nonce"] as? String, "n")
        let args = try XCTUnwrap(json["args"] as? [String: Any])
        XCTAssertEqual(args["pid"] as? Int, 42)
        let sent = try XCTUnwrap(args["activity"] as? [String: Any])
        XCTAssertEqual(sent["type"] as? Int, 0)
        XCTAssertEqual(sent["name"] as? String, "Portal 2 with BEER")
        XCTAssertEqual((sent["timestamps"] as? [String: Any])?["start"] as? Int, 1_700_000_000)
        let assets = try XCTUnwrap(sent["assets"] as? [String: Any])
        XCTAssertEqual(assets["large_text"] as? String, "Portal 2")
        XCTAssertNotNil(assets["large_image"])
        XCTAssertNotNil(assets["small_image"])
        let buttons = try XCTUnwrap(sent["buttons"] as? [[String: String]])
        XCTAssertEqual(buttons, [["label": "Get BEER", "url": "https://github.com/JarJarJames/BEER"]])
    }

    func testFrameIsLittleEndianOpcodeAndLengthThenBody() {
        let body = Data("{}".utf8)
        let frame = DiscordPresence.frame(.frame, body)

        XCTAssertEqual(Array(frame), [1, 0, 0, 0, 2, 0, 0, 0] + Array(body))
    }

    func testHandshakeNamesTheApplication() throws {
        let data = try DiscordPresence.handshake(clientID: "123")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["v"] as? Int, 1)
        XCTAssertEqual(json["client_id"] as? String, "123")
    }

    func testErrorReplyIsSurfaced() {
        let reply = Data(#"{"cmd":"SET_ACTIVITY","evt":"ERROR","data":{"code":4000,"message":"child \"activity\" fails"}}"#.utf8)
        let ok = Data(#"{"cmd":"SET_ACTIVITY","evt":null,"data":{}}"#.utf8)

        XCTAssertEqual(DiscordPresence.errorMessage(in: reply), "child \"activity\" fails")
        XCTAssertNil(DiscordPresence.errorMessage(in: ok))
    }
}
