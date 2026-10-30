import XCTest
@testable import BEER

final class ControllerRoutingTests: XCTestCase {
    private var wineRoot: URL!

    override func setUpWithError() throws {
        wineRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: wineRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wineRoot)
    }

    func testFindsWinebusUnderTheWineRoot() throws {
        let unix = wineRoot.appendingPathComponent("lib/wine/x86_64-unix")
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
        XCTAssertNil(ControllerSupport.winebusDirectory(wineRoot: wineRoot))

        try Data().write(to: unix.appendingPathComponent("winebus.so"))
        XCTAssertEqual(ControllerSupport.winebusDirectory(wineRoot: wineRoot)?.standardizedFileURL, unix.standardizedFileURL)
    }

    func testInstallsSDLBesideWinebusAndReplacesAnOlderCopy() throws {
        let library = wineRoot.appendingPathComponent("built.dylib")
        let destination = wineRoot.appendingPathComponent(ControllerSupport.sdlLibraryName)

        try Data([1]).write(to: library)
        try ControllerSupport.installSDL(library, into: wineRoot)
        XCTAssertEqual(try Data(contentsOf: destination), Data([1]))

        try Data([2]).write(to: library)
        try ControllerSupport.installSDL(library, into: wineRoot)
        XCTAssertEqual(try Data(contentsOf: destination), Data([2]))
    }

    func testLeavesAnIdenticalCopyAlone() throws {
        let library = wineRoot.appendingPathComponent("built.dylib")
        let destination = wineRoot.appendingPathComponent(ControllerSupport.sdlLibraryName)
        try Data([1]).write(to: library)
        try ControllerSupport.installSDL(library, into: wineRoot)
        let installed = try FileManager.default.attributesOfItem(atPath: destination.path)[.creationDate] as? Date

        try ControllerSupport.installSDL(library, into: wineRoot)

        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.creationDate] as? Date, installed)
    }

    @MainActor
    func testOverridesNoLongerLoadAControllerShim() {
        XCTAssertFalse(BottleStore().dllOverrides(for: .automatic, userOverrides: nil).contains("hid"))
    }
}
