import XCTest
@testable import BEER

final class DepotDownloaderOutputParsingTests: XCTestCase {
    func testAppLevelNotOwnedIsDetected() {
        XCTAssertEqual(
            parseNotOwned("App 3368600 (Brushes with Death) is not available from this account."),
            "Brushes with Death")
    }

    /// Regression: Kenshi's log contains this line yet downloads fine.
    func testOptionalDepotLineIsNotTreatedAsNotOwned() {
        XCTAssertNil(parseNotOwned("Depot 468550 is not available from this account."))
    }

    func testUnrelatedLineIsIgnored() {
        XCTAssertNil(parseNotOwned("Got 521 licenses for account!"))
    }

    /// Regression: the status stayed on the last file's "Pre-allocating" for
    /// the whole download, since chunk lines carry only a percentage.
    func testStatusMovesToDownloadingOnceChunksArrive() {
        let game = "/Volumes/BEERTestingAparatus2/BEER/Games/Easy Delivery Co."
        let shown = statuses(for: [
            "Downloading depot 3293011",
            "Pre-allocating \(game)/UnityCrashHandler64.exe",
            "Pre-allocating \(game)/UnityPlayer.dll",
            "  0.42% \(game)/UnityPlayer.dll",
            " 46.12% \(game)/EasyDeliveryCo_Data/sharedassets0.assets",
            " 52.65% \(game)/EasyDeliveryCo_Data/resources.assets",
            "Depot 3293011 - Downloaded 460725312 bytes (550270086 bytes uncompressed)",
        ])
        XCTAssertEqual(shown, ["Downloading…", "Pre-allocating disk space…", "Downloading…"])
    }

    /// Reinstall / Validate over files already there: "Validating" per file,
    /// then chunks for whatever was missing or changed.
    func testValidatingGivesWayToDownloading() {
        let game = "/Volumes/BEERTestingAparatus2/BEER/Games/DRIVE Rally"
        let shown = statuses(for: [
            "Validating \(game)/UnityCrashHandler64.exe",
            "Validating \(game)/UnityPlayer.dll",
            " 46.12% \(game)/UnityPlayer.dll",
            " 46.13% \(game)/UnityPlayer.dll",
        ])
        XCTAssertEqual(shown, ["Validating files…", "Downloading…"])
    }

    /// A game with several depots pre-allocates each in turn.
    func testNextDepotShowsItsOwnPreparation() {
        let shown = statuses(for: [
            "Pre-allocating C:/game/a.pak",
            " 99.00% C:/game/a.pak",
            "Downloading depot 250911",
            "Pre-allocating C:/game/b.pak",
            " 10.00% C:/game/b.pak",
        ])
        XCTAssertEqual(shown, ["Pre-allocating disk space…", "Downloading…", "Pre-allocating disk space…", "Downloading…"])
    }

    func testHeaderLabelCarriesThePercentage() {
        var entry = DownloadsStore.Entry(id: 1, name: "Game", bottleID: UUID(), status: .running("Downloading…"),
                                         fraction: 0, logTail: [], startedAt: Date())
        XCTAssertEqual(entry.phaseWithPercent, "Downloading…")
        entry.fraction = 0.5265
        XCTAssertEqual(entry.phaseWithPercent, "Downloading… 53%")
        entry.status = .completed
        XCTAssertEqual(entry.phaseWithPercent, "Installed")
    }

    /// The statuses BEER would show, in order, for `lines`.
    private func statuses(for lines: [String]) -> [String] {
        var status = DepotDownloaderStatus()
        return lines.compactMap { status.update(with: $0) }
    }
}
