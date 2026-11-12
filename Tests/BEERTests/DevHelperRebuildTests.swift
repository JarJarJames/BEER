import XCTest
@testable import BEER

/// When `swift run` couldn't rebuild the CloudSync helper, BEER finishes the
/// rebuild at launch. These check when it does and what it runs, against a
/// fake checkout in a temp folder; nothing is built.
final class DevHelperRebuildTests: XCTestCase {
    private var checkout: URL!
    private var publish: URL!

    override func setUpWithError() throws {
        checkout = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevHelperRebuildTests-\(UUID().uuidString)", isDirectory: true)
        publish = checkout.appendingPathComponent(
            ".build/plugins/outputs/beer/BEER/destination/CloudSyncPrebuild/CloudSyncPrebuildOutput/publish",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: publish, withIntermediateDirectories: true)
        try Data().write(to: publish.appendingPathComponent("CloudSync"))
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data().write(to: checkout.appendingPathComponent("scripts/cloudsync_prebuild.sh"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: checkout)
    }

    func testNothingToDoWhenThePluginBuiltTheHelper() {
        XCTAssertNil(DevHelperRebuild.plan(in: checkout))
    }

    func testRerunsThePluginScriptWhenItLeftTheNote() throws {
        try Data().write(to: publish.appendingPathComponent(DevHelperRebuild.markerName))

        let plan = try XCTUnwrap(DevHelperRebuild.plan(in: checkout))

        // /var and /private/var are the same folder; the file search reports the latter.
        func resolved(_ url: URL) -> String { url.resolvingSymlinksInPath().path }
        let output = publish.deletingLastPathComponent()
        XCTAssertEqual(resolved(plan.script), resolved(checkout.appendingPathComponent("scripts/cloudsync_prebuild.sh")))
        XCTAssertEqual(resolved(plan.outputDirectory), resolved(output))
        // The plugin's stamp sits in its work directory, beside the output.
        XCTAssertEqual(plan.stamp.lastPathComponent, "last-run.stamp")
        XCTAssertEqual(resolved(plan.stamp.deletingLastPathComponent()), resolved(output.deletingLastPathComponent()))
    }

    func testNothingToDoOutsideACheckout() throws {
        try Data().write(to: publish.appendingPathComponent(DevHelperRebuild.markerName))
        try FileManager.default.removeItem(at: checkout.appendingPathComponent("scripts"))
        XCTAssertNil(DevHelperRebuild.plan(in: checkout))
    }

    func testTheScriptWritesTheNoteTheAppLooksFor() throws {
        let script = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/cloudsync_prebuild.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("NEEDS_REBUILD=\"$OUT_DIR/publish/\(DevHelperRebuild.markerName)\""))
    }
}
