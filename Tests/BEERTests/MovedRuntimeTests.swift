import XCTest
@testable import BEER

/// A bottle whose runtime's files moved within its Runtimes/ folder (a
/// downloaded build unpacks one folder deeper than a hand-copied one) finds
/// them again; one whose runtime is gone is reported missing. Uses a temp
/// folder for Runtimes/.
final class MovedRuntimeTests: XCTestCase {
    private var runtimes: URL!

    override func setUpWithError() throws {
        runtimes = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovedRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimes, withIntermediateDirectories: true)
        // The temp folder is behind /var → /private/var, and the scanner
        // reports resolved paths. Application Support has no such link.
        let resolved = try XCTUnwrap(realpath(runtimes.path, nil))
        defer { free(resolved) }
        runtimes = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: runtimes)
    }

    /// A Wine build's bin folder (wine64 next to wineserver) at `relativePath`.
    private func makeRuntime(at relativePath: String) throws {
        let bin = runtimes.appendingPathComponent(relativePath, isDirectory: true).appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for tool in ["wine64", "wineserver"] {
            let path = bin.appendingPathComponent(tool).path
            XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: Data(), attributes: [.posixPermissions: 0o755]))
        }
    }

    /// A bottle made on the runtime as `ManagedRuntimeScanner` found it at `relativePath`.
    private func bottle(onRuntimeAt relativePath: String) -> Bottle {
        let wine = runtimes.appendingPathComponent(relativePath).appendingPathComponent("bin/wine64").path
        let folder = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
        return Bottle.make(
            name: "Isaac",
            runtime: RuntimeCandidate(kind: .systemWine, executablePath: wine, displayName: "Managed \(folder)",
                                      entrypoints: RuntimeEntrypoints(wine: wine, wineboot: nil, wineserver: nil)),
            graphicsBackend: .automatic
        )
    }

    func testRuntimeOneFolderDeeperIsFoundAgain() throws {
        let isaac = bottle(onRuntimeAt: "GPTK-4.0b3-winecx-26.3.0")
        try makeRuntime(at: "GPTK-4.0b3-winecx-26.3.0/gptk-4.0b3-winecx-26.3.0")

        XCTAssertTrue(isaac.runtimeIsMissing)
        let moved = try XCTUnwrap(isaac.movedRuntime(in: runtimes))
        XCTAssertEqual(moved.executablePath,
                       runtimes.appendingPathComponent("GPTK-4.0b3-winecx-26.3.0/gptk-4.0b3-winecx-26.3.0/bin/wine64").path)
        XCTAssertEqual(moved.displayName, "Managed GPTK-4.0b3-winecx-26.3.0")

        var relinked = isaac
        relinked.useRuntime(moved)
        XCTAssertFalse(relinked.runtimeIsMissing)
        XCTAssertNil(relinked.movedRuntime(in: runtimes))
    }

    func testRuntimeStillInPlaceIsLeftAlone() throws {
        try makeRuntime(at: "GPTK-4.0b3-winecx-26.3.0")
        let isaac = bottle(onRuntimeAt: "GPTK-4.0b3-winecx-26.3.0")

        XCTAssertFalse(isaac.runtimeIsMissing)
        XCTAssertNil(isaac.movedRuntime(in: runtimes))
    }

    func testDeletedRuntimeIsMissingWithNothingToRelink() {
        let isaac = bottle(onRuntimeAt: "GPTK-4.0b3-winecx-26.3.0")

        XCTAssertTrue(isaac.runtimeIsMissing)
        XCTAssertNil(isaac.movedRuntime(in: runtimes))
    }

    /// Another runtime folder's Wine is never picked up: switching a game to a
    /// different Wine is the player's call.
    func testOtherRuntimeFoldersAreNotUsed() throws {
        try makeRuntime(at: "GPTK-Game-Porting-Toolkit-3.0-3/wine")
        let isaac = bottle(onRuntimeAt: "GPTK-4.0b3-winecx-26.3.0")

        XCTAssertNil(isaac.movedRuntime(in: runtimes))
    }

    func testRuntimeOutsideRuntimesFolderIsNotSearched() {
        let crossOver = Bottle.make(
            name: "Game",
            runtime: RuntimeCandidate(kind: .crossOver, executablePath: "/nonexistent/CrossOver/bin/wine64", displayName: "CrossOver wine64"),
            graphicsBackend: .automatic
        )

        XCTAssertTrue(crossOver.runtimeIsMissing)
        XCTAssertNil(crossOver.movedRuntime(in: runtimes))
    }
}
