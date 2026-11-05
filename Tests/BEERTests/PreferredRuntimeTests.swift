import XCTest
@testable import BEER

/// The runtime new games get: BEER's own GPTK build where this macOS can run
/// it, then any GPTK, then whatever is installed.
@MainActor
final class PreferredRuntimeTests: XCTestCase {
    private let beer = RuntimeCandidate(kind: .systemWine, executablePath: "/R/GPTK-4.0b3-winecx-26.3.0/bin/wine64",
                                        displayName: "Managed GPTK-4.0b3-winecx-26.3.0")
    private let gcenx = RuntimeCandidate(kind: .systemWine, executablePath: "/R/GPTK-Game-Porting-Toolkit-3.0-3/wine/bin/wine64",
                                         displayName: "Managed GPTK-Game-Porting-Toolkit-3.0-3")
    private let wine = RuntimeCandidate(kind: .systemWine, executablePath: "/R/wine-devel-11.10/bin/wine64",
                                        displayName: "Managed Wine Devel 11.10")

    private func manifest(minimumMacOS: Int) -> BEERRuntimeManifest {
        BEERRuntimeManifest(d3dMetalVersion: "4.0b3", crossOverSourceVersion: "26.3.0", minimumMacOS: minimumMacOS)
    }

    private func preferred(_ candidates: [RuntimeCandidate], macOS: Int,
                           manifests: [String: BEERRuntimeManifest]) -> RuntimeCandidate? {
        ToolchainDetector.preferredGameRuntime(in: candidates, macOSMajorVersion: macOS, manifest: { manifests[$0] })
    }

    func testBEERBuildPreferredOverOtherGPTK() {
        // Alphabetically the Gcenx build sorts first among the candidates, as the detector lists them.
        let pick = preferred([wine, gcenx, beer], macOS: 15, manifests: [beer.executablePath: manifest(minimumMacOS: 15)])
        XCTAssertEqual(pick, beer)
    }

    func testBEERBuildSkippedWhereMacOSTooOld() {
        let pick = preferred([beer, gcenx, wine], macOS: 14, manifests: [beer.executablePath: manifest(minimumMacOS: 15)])
        XCTAssertEqual(pick, gcenx)
    }

    func testOnlyAnUnsupportedBEERBuildMeansNoRuntime() {
        XCTAssertNil(preferred([beer], macOS: 14, manifests: [beer.executablePath: manifest(minimumMacOS: 15)]))
    }

    func testNewestBEERBuildWins() {
        let newer = RuntimeCandidate(kind: .systemWine, executablePath: "/R/GPTK-4.0b10-winecx-26.4.0/bin/wine64",
                                     displayName: "Managed GPTK-4.0b10-winecx-26.4.0")
        let manifests = [beer.executablePath: manifest(minimumMacOS: 15), newer.executablePath: manifest(minimumMacOS: 15)]
        XCTAssertEqual(preferred([beer, newer, gcenx], macOS: 15, manifests: manifests), newer)
    }

    func testWithoutBEERBuildsFallsBackToGPTK() {
        XCTAssertEqual(preferred([wine, gcenx], macOS: 15, manifests: [:]), gcenx)
    }

    /// The manifest file as scripts/build_gptk_runtime.sh writes it, found
    /// from the runtime's wine binary.
    func testManifestReadFromRuntimeRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreferredRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let wine64 = bin.appendingPathComponent("wine64").path

        XCTAssertNil(ManagedRuntimeScanner.manifest(forWineBinary: wine64))

        try """
        {
          "d3dMetalVersion": "4.0b3",
          "crossOverSourceVersion": "26.3.0",
          "minimumMacOS": 15
        }
        """.write(to: root.appendingPathComponent(BEERRuntimeManifest.fileName), atomically: true, encoding: .utf8)
        XCTAssertEqual(ManagedRuntimeScanner.manifest(forWineBinary: wine64), manifest(minimumMacOS: 15))
    }
}
