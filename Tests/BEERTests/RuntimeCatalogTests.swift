import XCTest
@testable import BEER

/// Which GPTK builds the Runtimes tab and the game page offer, against faked
/// GitHub answers: BEER's own build first where macOS can run it, Gcenx's
/// otherwise, and Gcenx's still when BEER's can't be reached.
@MainActor
final class RuntimeCatalogTests: XCTestCase {
    private var requested: [URL] = []

    override func setUp() {
        requested = []
    }

    private func release(tag: String, asset: String) -> [String: Any] {
        [
            "tag_name": tag, "name": tag, "html_url": "https://github.com/example/\(tag)",
            "assets": [[
                "name": asset, "size": 254_000_000, "digest": "sha256:abc",
                "browser_download_url": "https://github.com/example/\(asset)"
            ]]
        ]
    }

    /// An installer whose GitHub answers come from `answers` (by URL); any
    /// other URL gets a 404.
    private func installer(macOS: Int, answers: [URL: [[String: Any]]]) -> RuntimeInstaller {
        RuntimeInstaller(fetch: { [unowned self] request in
            let url = request.url!
            requested.append(url)
            guard let body = answers[url] else {
                return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            return (try JSONSerialization.data(withJSONObject: body),
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, macOSMajorVersion: macOS)
    }

    private var bothCatalogs: [URL: [[String: Any]]] {
        [
            RuntimeSources.beerGPTKReleases: [release(tag: "4.0b3-winecx-26.3.0", asset: "gptk-4.0b3-winecx-26.3.0.tar.xz")],
            RuntimeSources.gcenxGPTKReleases: [release(tag: "Game-Porting-Toolkit-3.0-3", asset: "game-porting-toolkit-3.0-3.tar.xz")],
            RuntimeSources.gcenxWineBuilds: []
        ]
    }

    func testBEERBuildLeadsOnMacOS15() async throws {
        let installer = installer(macOS: 15, answers: bothCatalogs)
        try await installer.loadCatalog()

        XCTAssertEqual(installer.availableReleases.map(\.tag), ["4.0b3-winecx-26.3.0", "Game-Porting-Toolkit-3.0-3"])
        XCTAssertEqual(installer.latestGPTK?.tag, "4.0b3-winecx-26.3.0")
        // The folder it installs into is the one the build script's runtime is named for.
        XCTAssertEqual(installer.latestGPTK?.installDirName, "GPTK-4.0b3-winecx-26.3.0")
        XCTAssertEqual(installer.latestGPTK?.digest, "sha256:abc")
    }

    func testOlderMacOSNeverAsksForBEERBuild() async throws {
        let installer = installer(macOS: 14, answers: bothCatalogs)
        try await installer.loadCatalog()

        XCTAssertEqual(installer.availableReleases.map(\.tag), ["Game-Porting-Toolkit-3.0-3"])
        XCTAssertEqual(installer.latestGPTK?.tag, "Game-Porting-Toolkit-3.0-3")
        XCTAssertFalse(requested.contains(RuntimeSources.beerGPTKReleases))
    }

    func testGcenxStillListedWhenBEERReleasesUnreachable() async throws {
        var answers = bothCatalogs
        answers[RuntimeSources.beerGPTKReleases] = nil   // 404
        let installer = installer(macOS: 15, answers: answers)
        try await installer.loadCatalog()

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
