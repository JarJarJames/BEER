import CryptoKit
import XCTest
@testable import BEER

// Restoring a save backup: the current saves are backed up first, the backup's
// copies go back where they came from, and every sync then stops until the
// player chooses between the restored saves and Steam Cloud's. Everything here
// is on disk in a temporary folder; cloud listings are built by hand and
// nothing talks to Steam.
@MainActor
final class CloudSaveRestoreTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var installDir: URL!
    private var saves: URL!
    private var backups: URL!
    private let appID = 379430
    private let cloudName = "%WinSavedGames%/kingdomcome/saves/quicksave.whs"

    override func setUpWithError() throws {
        // The real path: folder listings report /private/var for /var, and a
        // bottle's own paths have no such link in them. (`resolvingSymlinksInPath`
        // strips /private back off, so it can't be used here.)
        let temp = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(temp) }
        root = URL(fileURLWithPath: String(cString: temp), isDirectory: true)
            .appendingPathComponent("CloudSaveRestoreTests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("drive_c/users/crossover", isDirectory: true)
        installDir = root.appendingPathComponent("drive_c/Games/KCD", isDirectory: true)
        saves = home.appendingPathComponent("Saved Games/kingdomcome/saves", isDirectory: true)
        backups = root.appendingPathComponent("CloudSaveBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        try Data("chapter 3".utf8).write(to: saves.appendingPathComponent("quicksave.whs"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Listing and planning

    func testSnapshotRecordsWhereEachFolderCameFrom() throws {
        let snapshot = try XCTUnwrap(engine().backUpBeforeWriting(appID: appID, dirs: [saves], label: "before-pull"))

        let stored = CloudSyncEngine.storedFolders(in: snapshot)
        XCTAssertEqual(stored.map(\.tail), ["Saved Games/kingdomcome/saves"])
        XCTAssertEqual(stored.first?.recorded, saves.path)
    }

    func testBackupsListShowsTriggerAndFileCountAndSkipsEmptyOnes() throws {
        let engine = engine()
        _ = try XCTUnwrap(engine.backUpBeforeWriting(appID: appID, dirs: [saves], label: "before-pull"))
        try FileManager.default.createDirectory(
            at: backups.appendingPathComponent("\(appID)/2020-01-01_10-00-00-before-sync"), withIntermediateDirectories: true
        )

        let list = engine.saveBackups(appID: appID)
        XCTAssertEqual(list.map(\.label), ["before-pull"])
        XCTAssertEqual(list.first?.fileCount, 1)
        XCTAssertEqual(SaveRestoreStrings.trigger("before-pull"), "Before a pull")
    }

    func testPlanSaysWhatTheRestoreReplaces() throws {
        let snapshot = try takeSnapshot()
        try write("chapter 5", to: "quicksave.whs")
        try write("new", to: "autosave.whs")

        let plan = try CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: installDir)

        XCTAssertEqual(plan.folders.map(\.target.path), [saves.path])
        XCTAssertEqual(plan.filesRestored, 1)
        XCTAssertEqual(plan.filesRemoved, 1, "autosave.whs isn't in the backup")
        XCTAssertNotNil(plan.currentLastChanged)
    }

    func testOldSnapshotFindsItsFolderWhenOnlyOneMatches() throws {
        let snapshot = try oldStyleSnapshot()

        let plan = try CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: installDir)

        XCTAssertEqual(plan.folders.map(\.target.lastPathComponent), ["saves"])
        XCTAssertTrue(CloudSyncEngine.isInside(plan.folders[0].target, saves))
    }

    func testOldSnapshotOfAClearedFolderFindsItsParent() throws {
        let snapshot = try oldStyleSnapshot()
        try FileManager.default.removeItem(at: saves)

        let plan = try CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: installDir)

        XCTAssertEqual(plan.folders.first?.target.path, saves.path)
    }

    func testOldSnapshotWithTwoMatchingFoldersIsNotGuessed() throws {
        let snapshot = try oldStyleSnapshot()
        try FileManager.default.createDirectory(
            at: installDir.appendingPathComponent("Saved Games/kingdomcome/saves"), withIntermediateDirectories: true
        )

        XCTAssertThrowsError(try CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: installDir)) { error in
            guard case CloudSyncError.restoreTargetUnknown = error else { return XCTFail("expected restoreTargetUnknown, got \(error)") }
        }
    }

    // A bottle's Documents is a link to the Mac's own Documents, and games
    // like Dark Souls save there. A walk doesn't follow links on its own.
    func testOldSnapshotFindsAFolderBehindTheDocumentsLink() throws {
        let macDocuments = root.appendingPathComponent("Mac Documents", isDirectory: true)
        let realFolder = macDocuments.appendingPathComponent("NBGI/DARK SOULS REMASTERED/185239630", isDirectory: true)
        try FileManager.default.createDirectory(at: realFolder, withIntermediateDirectories: true)
        try Data("bonfire".utf8).write(to: realFolder.appendingPathComponent("DRAKS0005.sl2"))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Documents"), withDestinationURL: macDocuments)
        let stored = backups.appendingPathComponent("\(appID)/2026-01-01_10-00-00-before-pull/NBGI/DARK SOULS REMASTERED/185239630",
                                                    isDirectory: true)
        try FileManager.default.createDirectory(at: stored, withIntermediateDirectories: true)
        try Data("firelink".utf8).write(to: stored.appendingPathComponent("DRAKS0005.sl2"))
        let snapshot = try XCTUnwrap(engine().saveBackups(appID: appID).first)

        let plan = try CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: installDir)
        XCTAssertEqual(plan.folders.map(\.target.path),
                       [home.appendingPathComponent("Documents/NBGI/DARK SOULS REMASTERED/185239630").path],
                       "reported under the bottle's path, the one Steam's cloud names map to")

        let engine = engine()
        try engine.restore(plan, appID: appID)
        XCTAssertEqual(try String(contentsOf: realFolder.appendingPathComponent("DRAKS0005.sl2"), encoding: .utf8), "firelink")
        let missing = CloudRemoteFile(filename: "%WinMyDocuments%/NBGI/DARK SOULS REMASTERED/185239630/DRAKS0006.sl2",
                                      size: 1, timestamp: Date(), sha: "deadbeef")
        XCTAssertEqual(engine.restoreConflict(appID: appID, remote: [missing], userHome: home, installDir: installDir)?
                           .differingCloudFiles.map(\.filename), [missing.filename])
    }

    // MARK: - Restoring

    func testRestoreBacksUpCurrentSavesThenPutsTheBackupBack() throws {
        let engine = engine()
        let snapshot = try takeSnapshot(engine)
        try write("chapter 5", to: "quicksave.whs")
        try write("new", to: "autosave.whs")

        try engine.restore(CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: installDir), appID: appID)

        XCTAssertEqual(try read("quicksave.whs"), "chapter 3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: saves.appendingPathComponent("autosave.whs").path))
        let before = try XCTUnwrap(engine.saveBackups(appID: appID).first { $0.label == CloudSaveBackupLimits.beforeRestoreLabel })
        XCTAssertEqual(try String(contentsOf: before.url.appendingPathComponent("Saved Games/kingdomcome/saves/quicksave.whs"), encoding: .utf8),
                       "chapter 5", "the saves the restore replaced are in a backup")
        XCTAssertEqual(engine.pendingRestore(appID: appID)?.snapshotName, snapshot.id)
    }

    func testRestoredFilesKeepTheBackupsDates() throws {
        let engine = engine()
        let snapshot = try takeSnapshot(engine)
        let stored = snapshot.url.appendingPathComponent("Saved Games/kingdomcome/saves/quicksave.whs")
        let then = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: stored.path)
        try write("chapter 5", to: "quicksave.whs")

        try engine.restore(CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: installDir), appID: appID)

        XCTAssertEqual(engine.fileMTime(saves.appendingPathComponent("quicksave.whs")), then)
    }

    func testFailedBackupLeavesSavesAloneAndNothingPending() throws {
        let engine = engine()
        let snapshot = try takeSnapshot(engine)
        try write("chapter 5", to: "quicksave.whs")
        let plan = try CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: installDir)
        // An unreadable save makes the copy before the restore fail.
        let locked = try write("locked", to: "locked.whs")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        XCTAssertThrowsError(try engine.restore(plan, appID: appID)) { error in
            guard case CloudSyncError.backupFailed = error else { return XCTFail("expected backupFailed, got \(error)") }
        }
        XCTAssertEqual(try read("quicksave.whs"), "chapter 5")
        XCTAssertNil(engine.pendingRestore(appID: appID))
    }

    func testRestoringTheOldestBackupDoesntPruneIt() throws {
        let engine = engine()
        engine.snapshotsToKeep = 1
        let snapshot = try oldStyleSnapshot(named: "2020-01-01_10-00-00-before-pull")
        try FileManager.default.createDirectory(at: backups.appendingPathComponent("\(appID)/2021-01-01_10-00-00-before-sync/x/y/z"),
                                                withIntermediateDirectories: true)
        try Data("other".utf8).write(to: backups.appendingPathComponent("\(appID)/2021-01-01_10-00-00-before-sync/x/y/z/f"))

        try engine.restore(CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: installDir), appID: appID)

        let names = engine.saveBackups(appID: appID).map(\.id)
        XCTAssertTrue(names.contains(snapshot.id), "the source of a pending restore stays until the player chooses")
        XCTAssertFalse(names.contains("2021-01-01_10-00-00-before-sync"), "the rest still follow the limit")
    }

    // MARK: - Settling with Steam Cloud

    func testNoPendingRestoreMeansNoConflict() throws {
        XCTAssertNil(engine().restoreConflict(appID: appID, remote: [remote(sha: "deadbeef")], userHome: home, installDir: installDir))
    }

    func testRestoredSavesMatchingSteamEndThePendingRestore() throws {
        let engine = try restoredEngine()

        XCTAssertNil(engine.restoreConflict(appID: appID, remote: [remote(sha: sha1(of: "chapter 3"))], userHome: home, installDir: installDir))
        XCTAssertNil(engine.pendingRestore(appID: appID), "nothing left to choose")
    }

    func testRestoredSavesDifferingFromSteamAreAConflict() throws {
        let engine = try restoredEngine()
        let uploaded = Date(timeIntervalSince1970: 1_800_000_000)

        let conflict = try XCTUnwrap(engine.restoreConflict(
            appID: appID, remote: [remote(sha: sha1(of: "chapter 5"), timestamp: uploaded)], userHome: home, installDir: installDir
        ))

        XCTAssertEqual(conflict.differingCloudFiles.map(\.filename), [cloudName])
        XCTAssertEqual(conflict.cloudLastUploaded, uploaded)
        XCTAssertEqual(conflict.localFileCount, 1)
        XCTAssertNotNil(engine.pendingRestore(appID: appID), "still waiting on the player")
    }

    func testSteamFileTheRestoreDoesntHaveIsAConflict() throws {
        let engine = try restoredEngine()
        let extra = CloudRemoteFile(filename: "%WinSavedGames%/kingdomcome/saves/autosave.whs", size: 3,
                                    timestamp: Date(), sha: sha1(of: "new"))

        let conflict = engine.restoreConflict(appID: appID, remote: [remote(sha: sha1(of: "chapter 3")), extra],
                                              userHome: home, installDir: installDir)

        XCTAssertEqual(conflict?.differingCloudFiles.map(\.filename), [extra.filename])
    }

    func testSteamFilesOutsideTheRestoredFoldersAreIgnored() throws {
        let engine = try restoredEngine()
        let elsewhere = CloudRemoteFile(filename: "%WinSavedGames%/kingdomcome/profiles/p.dat", size: 1,
                                        timestamp: Date(), sha: "deadbeef")

        XCTAssertNil(engine.restoreConflict(appID: appID, remote: [remote(sha: sha1(of: "chapter 3")), elsewhere],
                                            userHome: home, installDir: installDir))
    }

    func testChoosingSteamsSavesEndsThePendingRestore() throws {
        let engine = try restoredEngine()

        engine.useSteamSavesOverRestore(appID: appID)

        XCTAssertNil(engine.restoreConflict(appID: appID, remote: [remote(sha: "deadbeef")], userHome: home, installDir: installDir))
    }

    func testKeptRestoreUploadsSavesOlderThanSteamsStampedNow() throws {
        let save = saves.appendingPathComponent("quicksave.whs")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: save.path)
        let cloud = [remote(sha: "deadbeef", timestamp: Date(timeIntervalSince1970: 1_800_000_000))]
        let engine = engine()
        let cloudDirs: Set<URL> = [saves]

        let normal = engine.planUploads(remote: cloud, cloudDirs: cloudDirs, ruleMatches: [], userHome: home, installDir: installDir)
        let kept = engine.planUploads(remote: cloud, cloudDirs: cloudDirs, ruleMatches: [], userHome: home, installDir: installDir,
                                      forcing: [saves])

        XCTAssertTrue(normal.uploads.isEmpty, "an older save never goes up on its own")
        XCTAssertEqual(normal.skipped, 1)
        XCTAssertEqual(kept.uploads.map(\.filename), [cloudName])
        XCTAssertGreaterThan(try XCTUnwrap(kept.uploads.first).mtime, Date().addingTimeInterval(-60),
                             "stamped now, so Steam elsewhere doesn't see its own copy as newer")
    }

    func testKeptRestoreSkipsSavesAlreadyMatchingSteam() throws {
        let cloud = [remote(sha: sha1(of: "chapter 3"), timestamp: Date(timeIntervalSince1970: 1_800_000_000))]

        let plan = engine().planUploads(remote: cloud, cloudDirs: [saves], ruleMatches: [], userHome: home,
                                        installDir: installDir, forcing: [saves])

        XCTAssertTrue(plan.uploads.isEmpty)
        XCTAssertEqual(plan.skipped, 1)
    }

    // MARK: - helpers

    private func engine() -> CloudSyncEngine {
        let engine = CloudSyncEngine()
        engine.backupsDirectory = { [backups] appID in
            backups!.appendingPathComponent(String(appID), isDirectory: true)
        }
        return engine
    }

    /// An engine whose saves were just restored from a backup holding "chapter 3".
    private func restoredEngine() throws -> CloudSyncEngine {
        let engine = engine()
        let snapshot = try takeSnapshot(engine)
        try write("chapter 5", to: "quicksave.whs")
        try engine.restore(CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: installDir), appID: appID)
        return engine
    }

    private func takeSnapshot(_ engine: CloudSyncEngine? = nil) throws -> CloudSaveSnapshot {
        let engine = engine ?? self.engine()
        let url = try XCTUnwrap(engine.backUpBeforeWriting(appID: appID, dirs: [saves], label: "before-pull"))
        return try XCTUnwrap(engine.saveBackups(appID: appID).first { $0.url.lastPathComponent == url.lastPathComponent })
    }

    /// A snapshot as BEER made them before they recorded their folders.
    private func oldStyleSnapshot(named name: String = "2026-01-01_10-00-00-before-pull") throws -> CloudSaveSnapshot {
        let folder = backups.appendingPathComponent("\(appID)/\(name)/Saved Games/kingdomcome/saves", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("chapter 1".utf8).write(to: folder.appendingPathComponent("quicksave.whs"))
        return try XCTUnwrap(engine().saveBackups(appID: appID).first { $0.id == name })
    }

    @discardableResult
    private func write(_ text: String, to name: String) throws -> URL {
        let url = saves.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: saves.appendingPathComponent(name), encoding: .utf8)
    }

    private func remote(sha: String, timestamp: Date = Date()) -> CloudRemoteFile {
        CloudRemoteFile(filename: cloudName, size: 9, timestamp: timestamp, sha: sha)
    }

    private func sha1(of text: String) -> String {
        Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
