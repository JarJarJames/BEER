import XCTest
@testable import BEER

/// Which GPTK builds the Runtimes tab and the game page offer, against faked
/// GitHub answers: BEER's own builds in their own list (greyed out where
/// macOS can't run them), and `latestGPTK` BEER's where it can, Gcenx's
/// otherwise or when BEER's can't be reached.
@MainActor
final class RuntimeCatalogTests: XCTestCase {
    private func release(tag: String, asset: String, manifestURL: URL? = nil) -> [String: Any] {
        var assets: [[String: Any]] = [[
            "name": asset, "size": 254_000_000, "digest": "sha256:abc",
            "browser_download_url": "https://github.com/example/\(asset)"
        ]]
        if let manifestURL {
            assets.append([
                "name": BEERRuntimeManifest.fileName, "size": 90,
                "browser_download_url": manifestURL.absoluteString
            ])
        }
        return ["tag_name": tag, "name": tag, "html_url": "https://github.com/example/\(tag)", "assets": assets]
    }

    /// An installer whose GitHub answers come from `answers` (by URL); any
    /// other URL gets a 404.
    private func installer(macOS: Int, answers: [URL: Any]) -> RuntimeInstaller {
        RuntimeInstaller(fetch: { request in
            let url = request.url!
            guard let body = answers[url] else {
                return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            return (try JSONSerialization.data(withJSONObject: body),
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, macOSMajorVersion: macOS)
    }

    private var bothCatalogs: [URL: Any] {
        [
            RuntimeSources.beerGPTKReleases: [release(tag: "4.0b3-winecx-26.3.0", asset: "gptk-4.0b3-winecx-26.3.0.tar.xz")],
            RuntimeSources.gcenxGPTKReleases: [release(tag: "Game-Porting-Toolkit-3.0-3", asset: "game-porting-toolkit-3.0-3.tar.xz")],
            RuntimeSources.gcenxWineBuilds: []
        ]
    }

    func testBEERBuildLeadsOnMacOS15() async throws {
        let installer = installer(macOS: 15, answers: bothCatalogs)
        try await installer.loadCatalog()

        XCTAssertEqual(installer.beerReleases.map(\.tag), ["4.0b3-winecx-26.3.0"])
        XCTAssertEqual(installer.beerReleases.map(\.minimumMacOS), [RuntimeSources.beerGPTKMinimumMacOS])
        XCTAssertEqual(installer.availableReleases.map(\.tag), ["Game-Porting-Toolkit-3.0-3"])
        XCTAssertEqual(installer.latestGPTK?.tag, "4.0b3-winecx-26.3.0")
        // The folder it installs into is the one the build script's runtime is named for.
        XCTAssertEqual(installer.latestGPTK?.installDirName, "GPTK-4.0b3-winecx-26.3.0")
        XCTAssertEqual(installer.latestGPTK?.digest, "sha256:abc")
    }

    func testOlderMacOSListsBEERBuildButNeverOffersIt() async throws {
        let installer = installer(macOS: 14, answers: bothCatalogs)
        try await installer.loadCatalog()

        XCTAssertEqual(installer.beerReleases.map(\.tag), ["4.0b3-winecx-26.3.0"])
        XCTAssertFalse(installer.canRun(installer.beerReleases[0]))
        XCTAssertEqual(installer.availableReleases.map(\.tag), ["Game-Porting-Toolkit-3.0-3"])
        XCTAssertEqual(installer.latestGPTK?.tag, "Game-Porting-Toolkit-3.0-3")
    }

    /// A release's own `beer-runtime.json` beats the constant, in both
    /// directions: a build that runs on 14 is offered there, and one that
    /// needs a newer macOS is skipped for an older build that runs.
    func testReleaseManifestSetsMinimumMacOS() async throws {
        let forFourteen = URL(string: "https://github.com/example/new/beer-runtime.json")!
        let forTwentySeven = URL(string: "https://github.com/example/old/beer-runtime.json")!
        var answers = bothCatalogs
        answers[RuntimeSources.beerGPTKReleases] = [
            release(tag: "4.1-winecx-27.0.0", asset: "gptk-4.1-winecx-27.0.0.tar.xz", manifestURL: forTwentySeven),
            release(tag: "4.0b4-winecx-26.4.0", asset: "gptk-4.0b4-winecx-26.4.0.tar.xz", manifestURL: forFourteen)
        ]
        answers[forFourteen] = ["d3dMetalVersion": "4.0b4", "crossOverSourceVersion": "26.4.0", "minimumMacOS": 14]
        answers[forTwentySeven] = ["d3dMetalVersion": "4.1", "crossOverSourceVersion": "27.0.0", "minimumMacOS": 27]
        let installer = installer(macOS: 14, answers: answers)
        try await installer.loadCatalog()

        XCTAssertEqual(installer.beerReleases.map(\.minimumMacOS), [27, 14])
        XCTAssertEqual(installer.latestGPTK?.tag, "4.0b4-winecx-26.4.0")
    }

    func testUnreadableManifestFallsBackToConstant() async throws {
        var answers = bothCatalogs
        answers[RuntimeSources.beerGPTKReleases] = [
            release(tag: "4.0b3-winecx-26.3.0", asset: "gptk-4.0b3-winecx-26.3.0.tar.xz",
                    manifestURL: URL(string: "https://github.com/example/missing/beer-runtime.json")!)   // 404
        ]
        let installer = installer(macOS: 14, answers: answers)
        try await installer.loadCatalog()

        XCTAssertEqual(installer.beerReleases.map(\.minimumMacOS), [RuntimeSources.beerGPTKMinimumMacOS])
        XCTAssertEqual(installer.latestGPTK?.tag, "Game-Porting-Toolkit-3.0-3")
    }

    /// The Runtime Manager's badge, from the lists the catalog loaded, with
    /// nothing installed yet.
    private func recommendation(_ installer: RuntimeInstaller, macOS: Int) -> RuntimeRecommendation? {
        ToolchainDetector.recommendedRuntime(installed: [], beerReleases: installer.beerReleases,
                                             gptkReleases: installer.availableReleases,
                                             macOSMajorVersion: macOS, manifest: { _ in nil })
    }

    func testNewestBEERBuildRecommendedOnMacOS15() async throws {
        var answers = bothCatalogs
        answers[RuntimeSources.beerGPTKReleases] = [
            release(tag: "4.0b3-winecx-26.3.0-2", asset: "gptk-4.0b3-winecx-26.3.0-2.tar.xz"),
            release(tag: "4.0b3-winecx-26.3.0", asset: "gptk-4.0b3-winecx-26.3.0.tar.xz")
        ]
        let installer = installer(macOS: 15, answers: answers)
        try await installer.loadCatalog()

        XCTAssertEqual(recommendation(installer, macOS: 15), .release(installer.beerReleases[0]))
        XCTAssertEqual(installer.latestGPTK, installer.beerReleases[0])
    }

    func testNewestGcenxRecommendedOnMacOS14() async throws {
        var answers = bothCatalogs
        answers[RuntimeSources.gcenxGPTKReleases] = [
            release(tag: "Game-Porting-Toolkit-3.0-3", asset: "game-porting-toolkit-3.0-3.tar.xz"),
            release(tag: "Game-Porting-Toolkit-2.1", asset: "game-porting-toolkit-2.1.tar.xz")
        ]
        let installer = installer(macOS: 14, answers: answers)
        try await installer.loadCatalog()

        XCTAssertEqual(recommendation(installer, macOS: 14), .release(installer.availableReleases[0]))
        XCTAssertEqual(installer.latestGPTK, installer.availableReleases[0])
    }

    func testGcenxStillListedWhenBEERReleasesUnreachable() async throws {
        var answers = bothCatalogs
        answers[RuntimeSources.beerGPTKReleases] = nil   // 404
        let installer = installer(macOS: 15, answers: answers)
        try await installer.loadCatalog()

        XCTAssertEqual(installer.beerReleases, [])
        XCTAssertEqual(installer.latestGPTK?.tag, "Game-Porting-Toolkit-3.0-3")
    }

    func testGcenxUnreachableFailsTheCatalog() async {
        var answers = bothCatalogs
        answers[RuntimeSources.gcenxGPTKReleases] = nil
        let installer = installer(macOS: 15, answers: answers)

        do {
            try await installer.loadCatalog()
            XCTFail("expected the catalog to fail")
        } catch {
            guard case .releaseFetchFailed? = error as? RuntimeInstallerError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
