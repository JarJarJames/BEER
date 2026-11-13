import XCTest
@testable import BEER

final class AppVersionTests: XCTestCase {
    func testBundleVersionIsShown() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.6.2", "CFBundleVersion": "1"]
        XCTAssertEqual(AppVersion.label(info: info), "0.6.2")
        XCTAssertEqual(MainShellStrings.windowTitle(version: AppVersion.label(info: info)), "BEER 0.6.2")
    }

    // `swift run` has no Info.plist: no dictionary at all, or one without a version.
    func testNoBundleVersionShowsDev() {
        XCTAssertEqual(AppVersion.label(info: nil), "dev")
        XCTAssertEqual(AppVersion.label(info: ["CFBundleExecutable": "BEER"]), "dev")
        XCTAssertEqual(AppVersion.label(info: ["CFBundleShortVersionString": "  "]), "dev")
        XCTAssertEqual(MainShellStrings.windowTitle(version: AppVersion.label(info: nil)), "BEER dev")
    }
}
