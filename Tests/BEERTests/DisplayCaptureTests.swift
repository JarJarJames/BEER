import XCTest
@testable import BEER

final class DisplayCaptureTests: XCTestCase {
    func testCaptureIsOffByDefault() {
        let bottle = makeBottle()
        XCTAssertFalse(bottle.effectiveCaptureDisplayInFullscreen)
        XCTAssertEqual(bottle.captureDisplaysRegistryValue, "N")
    }

    func testCaptureOnWritesY() {
        var bottle = makeBottle()
        bottle.captureDisplayInFullscreen = true
        XCTAssertEqual(bottle.captureDisplaysRegistryValue, "Y")
    }

    func testBottleWithoutFieldDecodesAsOff() throws {
        var bottle = makeBottle()
        bottle.captureDisplayInFullscreen = true
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(bottle)) as? [String: Any]
        )
        object.removeValue(forKey: "captureDisplayInFullscreen")

        let decoded = try JSONDecoder().decode(Bottle.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.captureDisplayInFullscreen)
        XCTAssertEqual(decoded.captureDisplaysRegistryValue, "N")
    }

    func testCaptureSettingRoundTrips() throws {
        var bottle = makeBottle()
        bottle.captureDisplayInFullscreen = true
        let decoded = try JSONDecoder().decode(Bottle.self, from: JSONEncoder().encode(bottle))
        XCTAssertEqual(decoded.captureDisplayInFullscreen, true)
    }

    private func makeBottle() -> Bottle {
        Bottle.make(
            name: "Test",
            runtime: RuntimeCandidate(
                kind: .gameNativeWine,
                executablePath: "/tmp/wine",
                displayName: "Test Wine"
            ),
            graphicsBackend: .automatic
        )
    }
}
