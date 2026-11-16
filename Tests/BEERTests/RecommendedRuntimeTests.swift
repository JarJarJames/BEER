import XCTest
@testable import BEER

/// The runtime the Runtime Manager marks "Recommended for this Mac". It comes
/// from `preferredGameRuntime`, so once installed it's what new games get.
@MainActor
final class RecommendedRuntimeTests: XCTestCase {
    private let beerRelease = RuntimeRelease(
        family: .gptk, tag: "4.0b3-winecx-26.3.0-2", name: "4.0b3-winecx-26.3.0-2",
        assetName: "gptk-4.0b3-winecx-26.3.0-2.tar.xz", assetURL: URL(string: "https://example.com/beer.tar.xz")!,
        size: 1, digest: nil, htmlURL: URL(string: "https://example.com/beer")!, minimumMacOS: 15
    )
    private let gcenxRelease = RuntimeRelease(
        family: .gptk, tag: "Game-Porting-Toolkit-3.0-3", name: "Game-Porting-Toolkit-3.0-3",
        assetName: "game-porting-toolkit-3.0-3.tar.xz", assetURL: URL(string: "https://example.com/gcenx.tar.xz")!,
        size: 1, digest: nil, htmlURL: URL(string: "https://example.com/gcenx")!
    )
    /// The two releases as ManagedRuntimeScanner names them once installed.
    private let beer = RuntimeCandidate(kind: .systemWine, executablePath: "/R/GPTK-4.0b3-winecx-26.3.0-2/bin/wine64",
                                        displayName: "Managed GPTK-4.0b3-winecx-26.3.0-2")
    private let gcenx = RuntimeCandidate(kind: .systemWine, executablePath: "/R/GPTK-Game-Porting-Toolkit-3.0-3/wine/bin/wine64",
                                         displayName: "Managed GPTK-Game-Porting-Toolkit-3.0-3")
    private let wine = RuntimeCandidate(kind: .systemWine, executablePath: "/R/wine-devel-11.10/bin/wine64",
                                        displayName: "Managed Wine Devel 11.10")

    private var manifests: [String: BEERRuntimeManifest] {
        [beer.executablePath: BEERRuntimeManifest(d3dMetalVersion: "4.0b3", crossOverSourceVersion: "26.3.0", minimumMacOS: 15)]
    }

    private func recommended(installed: [RuntimeCandidate], macOS: Int) -> RuntimeRecommendation? {
        ToolchainDetector.recommendedRuntime(installed: installed, beerReleases: [beerRelease], gptkReleases: [gcenxRelease],
                                             macOSMajorVersion: macOS, manifest: { self.manifests[$0] })
    }

    private func preferred(_ installed: [RuntimeCandidate], macOS: Int) -> RuntimeCandidate? {
        ToolchainDetector.preferredGameRuntime(in: installed, macOSMajorVersion: macOS, manifest: { self.manifests[$0] })
    }

    func testBEERReleaseRecommendedOverInstalledGcenxOnMacOS15() {
        XCTAssertEqual(recommended(installed: [wine, gcenx], macOS: 15), .release(beerRelease))
    }

    func testInstalledGcenxRecommendedOnMacOS14() {
        // Even with BEER's build installed: this macOS can't run it.
        XCTAssertEqual(recommended(installed: [beer, gcenx, wine], macOS: 14), .installed(gcenx))
    }

    func testGcenxReleaseRecommendedOnMacOS14WithNothingInstalled() {
        XCTAssertEqual(recommended(installed: [], macOS: 14), .release(gcenxRelease))
    }

    func testInstalledReleaseIsBadgedInTheInstalledList() {
        XCTAssertEqual(recommended(installed: [gcenx, beer], macOS: 15), .installed(beer))
    }

    /// With every catalog release installed, the badge sits on exactly the
    /// runtime new games default to, on every macOS.
    func testBadgeAgreesWithPreferredGameRuntime() {
        for macOS in [14, 15, 26] {
            for installed in [[beer, gcenx, wine], [gcenx, wine, beer], [beer, wine, gcenx]] {
                let pick = preferred(installed, macOS: macOS)
                XCTAssertNotNil(pick)
                XCTAssertEqual(recommended(installed: installed, macOS: macOS), pick.map(RuntimeRecommendation.installed),
                               "macOS \(macOS), \(installed.map(\.displayName))")
            }
        }
    }
}
