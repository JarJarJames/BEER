import XCTest
@testable import BEER

/// BEER logs on to Steam once and runs everything through that session
/// (`SteamSessionHost`). Every extra logon is another session on the user's
/// account and counts toward Steam's rate limit.
@MainActor
final class SteamSessionHostTests: XCTestCase {
    private var root: URL!
    private var fakeSteam: FakeSteam!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteamSessionHostTests-\(UUID().uuidString)", isDirectory: true)
        fakeSteam = try FakeSteam(in: root.appendingPathComponent("FakeSteam", isDirectory: true))
    }

    override func tearDown() async throws {
        await fakeSteam.client.endSession()
        try? FileManager.default.removeItem(at: root)
    }

    func testEveryCommandSharesOneLogon() async throws {
        fakeSteam.installSizes = [1: 1_000]
        fakeSteam.clientIcons = [1: "abc"]
        fakeSteam.gameUpdates = [1: .current]
        let client = fakeSteam.client
        let folder: URL = root

        _ = try await client.enumerate(appID: 1, account: "someone", refreshToken: "token")
        _ = try await client.installSize(appIDs: [1], account: "someone", refreshToken: "token")
        // Requests in flight at once share it too.
        async let icon = client.clientIcon(appID: 1, account: "someone", refreshToken: "token")
        async let updates = client.updateCheck(
            games: [.init(appID: 1, directory: folder)], account: "someone", refreshToken: "token")
        let (iconURL, statuses) = try await (icon, updates)

        XCTAssertNotNil(iconURL)
        XCTAssertEqual(statuses, [1: .current])
        XCTAssertEqual(Set(fakeSteam.calls().map(\.command)), ["enumerate", "installsize", "clienticon", "updatecheck"])
        XCTAssertEqual(fakeSteam.logons(), 1)
    }

    func testARefusedLogonIsNotRetried() async throws {
        fakeSteam.logonRefused = true
        let client = fakeSteam.client

        for _ in 0..<3 {
            do {
                _ = try await client.enumerate(appID: 1, account: "someone", refreshToken: "token")
                XCTFail("expected the refused logon to throw")
            } catch CloudSyncClientError.authExpired {
            }
        }
        XCTAssertEqual(fakeSteam.logons(), 1, "logging on again with a refused token only deepens the block")
        XCTAssertTrue(fakeSteam.calls().isEmpty)
    }

    func testANewSignInGetsANewSession() async throws {
        let client = fakeSteam.client
        _ = try await client.enumerate(appID: 1, account: "someone", refreshToken: "old")
        _ = try await client.enumerate(appID: 1, account: "someone", refreshToken: "new")
        XCTAssertEqual(fakeSteam.logons(), 2)
    }

    func testRequestsCarryTheirArguments() throws {
        let line = try SteamSessionHost.requestLine(["enumerate", "--appid", "440", "--flag"], id: 7)
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(request["id"] as? Int, 7)
        XCTAssertEqual(request["cmd"] as? String, "enumerate")
        XCTAssertEqual(request["args"] as? [String: String], ["appid": "440", "flag": "true"])
    }
}
