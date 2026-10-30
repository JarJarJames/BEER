import XCTest
@testable import BEER

final class ControllerRoutingTests: XCTestCase {
    func testPlayStationPadsTakeTheSDLRoute() {
        for identifier in ["054c:05c4", "054c:09cc", "054c:0ba0", "054c:0ce6", "054c:0df2"] {
            XCTAssertTrue(ControllerSupport.usesSDLRoute([identifier]), identifier)
        }
    }

    func testOnePlayStationPadRoutesEveryPadThroughSDL() {
        XCTAssertTrue(ControllerSupport.usesSDLRoute(["045e:028e", "054c:0ce6"]))
    }

    /// Xbox and Steam pads work on the raw route, where the Steam Controller
    /// fix applies, so nothing changes for them.
    func testOtherPadsKeepTheRawRoute() {
        XCTAssertFalse(ControllerSupport.usesSDLRoute(["045e:028e", "045e:0b13"]))
        XCTAssertFalse(ControllerSupport.usesSDLRoute([]))
    }

    func testRegistryDisablesHidrawOnTheSDLRoute() {
        XCTAssertEqual(
            ControllerSupport.winebusRegistry(identifiers: ["045e:028e", "054c:0ce6"], sdlRoute: true),
            "REGEDIT4\r\n\r\n"
                + #"[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\winebus]"# + "\r\n"
                + #""EnableHidraw"="045e:028e,054c:0ce6""# + "\r\n"
                + #""DisableHidraw"=dword:00000001"# + "\r\n"
        )
    }

    /// Written even with no pads, so a previous launch's SDL route is undone.
    func testRegistryReEnablesHidrawOtherwise() {
        let registry = ControllerSupport.winebusRegistry(identifiers: [], sdlRoute: false)
        XCTAssertTrue(registry.contains(#""EnableHidraw"="""#))
        XCTAssertTrue(registry.contains(#""DisableHidraw"=dword:00000000"#))
    }
}
