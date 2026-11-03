import XCTest
@testable import BEER

/// Moving a game folder between "drives", which here are temporary folders on
/// one disk. `isSameVolume` is turned off so the copy-check-delete path runs
/// as it would between two real drives.
@MainActor
final class GameMoveTests: XCTestCase {
    private var root: URL!
    private var macGames: URL!
    private var driveGames: URL!
    private var journal: GameMoveJournal!
    private let bottleID = UUID()

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameMoveTests-\(UUID().uuidString)", isDirectory: true)
        macGames = root.appendingPathComponent("Bottle/drive_c/Games", isDirectory: true)
        driveGames = root.appendingPathComponent("Drive/BEER/Games", isDirectory: true)
        try FileManager.default.createDirectory(at: macGames, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: driveGames, withIntermediateDirectories: true)
        journal = GameMoveJournal(url: root.appendingPathComponent("game-moves.json"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func mover(sameVolume: Bool = false) -> GameMove {
        GameMove(journal: journal, gameFolderParents: [macGames, driveGames], isSameVolume: { _, _ in sameVolume })
    }

    /// A game with a big data file, a save, an executable and a symlink.
    private func makeGame() throws -> URL {
        let game = macGames.appendingPathComponent("Game", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: game.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try fm.createDirectory(at: game.appendingPathComponent("saves"), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 3 * GameFolderLimits.copyChunkBytes + 11).write(to: game.appendingPathComponent("data.pak"))
        try Data("level 9".utf8).write(to: game.appendingPathComponent("saves/slot1.sav"))
        try Data("MZ".utf8).write(to: game.appendingPathComponent("bin/Game.exe"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: game.appendingPathComponent("bin/Game.exe").path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
                             ofItemAtPath: game.appendingPathComponent("saves/slot1.sav").path)
        try fm.createSymbolicLink(atPath: game.appendingPathComponent("launcher").path, withDestinationPath: "bin/Game.exe")
        return game
    }

    private func record(from source: URL) -> GameMoveRecord {
        GameMoveRecord(bottleID: bottleID, source: source.path, sourceDrive: nil,
                       destination: driveGames.appendingPathComponent("Game").path, destinationDrive: nil, stage: .copying)
    }

    // MARK: - A move that works

    func testMoveCopiesChecksSwitchesThenDeletesTheOldCopy() async throws {
        let source = try makeGame()
        let record = record(from: source)
        var events: [String] = []

        let outcome = try await mover().run(
            record, cancel: CancelFlag(), progress: { _ in },
            switchBottle: {
                events.append("switch")
                XCTAssertTrue(FileManager.default.fileExists(atPath: record.destination + "/saves/slot1.sav"),
                              "the bottle only switches to a complete copy")
                XCTAssertEqual(self.journal.record(for: self.bottleID)?.stage, .copying)
            },
            backUpSaves: { folder in
                events.append("backup")
                XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path), "backed up before deleting")
            }
        )

        XCTAssertEqual(outcome, .moved)
        XCTAssertEqual(events, ["switch", "backup"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertTrue(journal.records().isEmpty)

        let moved = record.destinationURL
        let fm = FileManager.default
        XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("saves/slot1.sav")), Data("level 9".utf8))
        XCTAssertEqual(try fm.attributesOfItem(atPath: moved.appendingPathComponent("saves/slot1.sav").path)[.modificationDate] as? Date,
                       Date(timeIntervalSince1970: 1_000_000), "cloud sync compares saves by modification time")
        XCTAssertTrue(fm.isExecutableFile(atPath: moved.appendingPathComponent("bin/Game.exe").path))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: moved.appendingPathComponent("launcher").path), "bin/Game.exe")
        XCTAssertEqual((try fm.attributesOfItem(atPath: moved.appendingPathComponent("data.pak").path)[.size] as? NSNumber)?.intValue,
                       3 * GameFolderLimits.copyChunkBytes + 11)
    }

    func testMoveOnOneDiskIsARename() async throws {
        let source = try makeGame()
        let record = record(from: source)
        var switched = false

        let outcome = try await mover(sameVolume: true).run(
            record, cancel: CancelFlag(), progress: { _ in XCTFail("nothing to copy") },
            switchBottle: { switched = true }, backUpSaves: { _ in XCTFail("no old copy to delete") }
        )

        XCTAssertEqual(outcome, .moved)
        XCTAssertTrue(switched)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.destination + "/data.pak"))
        XCTAssertTrue(journal.records().isEmpty)
    }

    func testProgressCountsEveryByte() async throws {
        let source = try makeGame()
        let updates = ProgressLog()
        _ = try await mover().run(record(from: source), cancel: CancelFlag(), progress: updates.append,
                                  switchBottle: {}, backUpSaves: { _ in })
        let copying = updates.all.filter { $0.phase == .copying }
        XCTAssertEqual(copying.last?.copiedBytes, copying.last?.totalBytes)
        XCTAssertGreaterThan(copying.count, 3, "moves during a big file, not only between files")
        XCTAssertTrue(updates.all.contains { $0.phase == .checking })
    }

    // MARK: - A move that stops

    func testCancelLeavesTheGameWhereItWas() async throws {
        let source = try makeGame()
        let record = record(from: source)
        let cancel = CancelFlag()
        cancel.cancel()

        do {
            _ = try await mover().run(record, cancel: cancel, progress: { _ in },
                                      switchBottle: { XCTFail("never switched") }, backUpSaves: { _ in })
            XCTFail("expected the move to stop")
        } catch {
            XCTAssertEqual(error as? GameFolderError, .cancelled)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("saves/slot1.sav").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.stagingURL.path), "the partial copy is gone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.destination))
        XCTAssertTrue(journal.records().isEmpty)
    }

    func testFailedBottleSaveThrowsTheCopyAway() async throws {
        let source = try makeGame()
        let record = record(from: source)

        do {
            _ = try await mover().run(record, cancel: CancelFlag(), progress: { _ in },
                                      switchBottle: { throw CocoaError(.fileWriteNoPermission) }, backUpSaves: { _ in })
            XCTFail("expected the move to fail")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("data.pak").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.destination))
        XCTAssertTrue(journal.records().isEmpty)
    }

    func testOldCopyIsKeptWhenItsSavesCantBeBackedUp() async throws {
        let source = try makeGame()
        let outcome = try await mover().run(record(from: source), cancel: CancelFlag(), progress: { _ in },
                                            switchBottle: {}, backUpSaves: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        guard case .movedKeptOldCopy = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("saves/slot1.sav").path))
    }

    func testOnlyBEERsGameFoldersAreDeleted() async throws {
        // A source outside every Games folder BEER knows is never deleted.
        let elsewhere = root.appendingPathComponent("Somewhere/Game", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: elsewhere.appendingPathComponent("file"))

        let outcome = try await mover().run(record(from: elsewhere), cancel: CancelFlag(), progress: { _ in },
                                            switchBottle: {}, backUpSaves: { _ in })
        guard case .movedKeptOldCopy = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("file").path))
    }

    func testNeverMovesOntoAnExistingFolder() async throws {
        let source = try makeGame()
        let record = record(from: source)
        try FileManager.default.createDirectory(at: record.destinationURL, withIntermediateDirectories: true)

        do {
            _ = try await mover().run(record, cancel: CancelFlag(), progress: { _ in }, switchBottle: {}, backUpSaves: { _ in })
            XCTFail("expected a refusal")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: - The check

    func testCheckCatchesAChangedSave() throws {
        let source = try makeGame()
        let copy = root.appendingPathComponent("Copy", isDirectory: true)
        try FolderCopier.copy(try FolderCopier.inventory(of: source), from: source, to: copy, progress: { _ in }, isCancelled: { false })
        XCTAssertNoThrow(try FolderCopier.verify(copy, against: source))

        // Same size, different bytes: only a byte compare sees it.
        try Data("level 1".utf8).write(to: copy.appendingPathComponent("saves/slot1.sav"))
        XCTAssertThrowsError(try FolderCopier.verify(copy, against: source)) {
            XCTAssertEqual($0 as? GameFolderError, .copyMismatch("saves/slot1.sav"))
        }
    }

    func testCheckCatchesAMissingFile() throws {
        let source = try makeGame()
        let copy = root.appendingPathComponent("Copy", isDirectory: true)
        try FolderCopier.copy(try FolderCopier.inventory(of: source), from: source, to: copy, progress: { _ in }, isCancelled: { false })
        try FileManager.default.removeItem(at: copy.appendingPathComponent("bin/Game.exe"))
        XCTAssertThrowsError(try FolderCopier.verify(copy, against: source))
    }

    // MARK: - After a crash

    func testCrashBeforeTheSwitchThrowsTheCopyAway() async throws {
        let source = try makeGame()
        var record = record(from: source)
        record.stage = .copying
        journal.save(record)
        try FileManager.default.createDirectory(at: record.stagingURL, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: record.stagingURL.appendingPathComponent("data.pak"))

        let done = await mover().recover(record, bottleDirectory: source, backUpSaves: { _ in XCTFail("nothing deleted from the game") })

        XCTAssertTrue(done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("saves/slot1.sav").path))
        XCTAssertTrue(journal.records().isEmpty)
    }

    func testCrashAfterTheRenameButBeforeTheSaveKeepsTheOriginal() async throws {
        // The copy was renamed into place but the bottle was never saved
        // pointing at it: the game still runs from the original.
        let source = try makeGame()
        let record = record(from: source)
        journal.save(record)
        try FileManager.default.copyItem(at: source, to: record.destinationURL)

        let done = await mover().recover(record, bottleDirectory: source, backUpSaves: { _ in })

        XCTAssertTrue(done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.destination))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCrashAfterTheSwitchFinishesDeletingTheOldCopy() async throws {
        let source = try makeGame()
        var record = record(from: source)
        record.stage = .switched
        journal.save(record)
        try FileManager.default.copyItem(at: source, to: record.destinationURL)
        var backedUp: URL?

        let done = await mover().recover(record, bottleDirectory: record.destinationURL, backUpSaves: { backedUp = $0 })

        XCTAssertTrue(done)
        XCTAssertEqual(backedUp, source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.destination + "/saves/slot1.sav"))
        XCTAssertTrue(journal.records().isEmpty)
    }

    func testRecoveryWaitsForAnUnpluggedDrive() async throws {
        let source = try makeGame()
        let unplugged = URL(fileURLWithPath: "/Volumes/BEER-Test-\(UUID().uuidString)/BEER/Games/Game", isDirectory: true)
        let record = GameMoveRecord(bottleID: bottleID, source: source.path, sourceDrive: nil,
                                    destination: unplugged.path, destinationDrive: nil, stage: .copying)
        journal.save(record)

        let done = await mover().recover(record, bottleDirectory: source, backUpSaves: { _ in })

        XCTAssertFalse(done)
        XCTAssertEqual(journal.records(), [record], "kept for when the drive is back")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCrashAfterTheSwitchNeverDeletesTheNewCopy() async throws {
        // Recorded as switched, and the game was removed meanwhile (or the
        // bottle list didn't load): the new copy is the game, so it stays.
        let source = try makeGame()
        var record = record(from: source)
        record.stage = .switched
        try FileManager.default.copyItem(at: source, to: record.destinationURL)

        let done = await mover().recover(record, bottleDirectory: nil, backUpSaves: { _ in })

        XCTAssertTrue(done)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.destination + "/saves/slot1.sav"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testOldCopyWaitsUntilTheNewOneIsBack() async throws {
        // Switched, but the drive it moved to isn't here: deleting the old
        // copy now would leave no copy at hand.
        let source = try makeGame()
        var record = record(from: source)
        record.stage = .switched
        journal.save(record)

        let done = await mover().recover(record, bottleDirectory: record.destinationURL, backUpSaves: { _ in })

        XCTAssertFalse(done)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("saves/slot1.sav").path))
        XCTAssertEqual(journal.records(), [record])
    }

    func testUnfinishedMoveOfARemovedGameKeepsTheCopy() async throws {
        let source = try makeGame()
        let record = record(from: source)
        try FileManager.default.createDirectory(at: record.stagingURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: record.destinationURL)

        let done = await mover().recover(record, bottleDirectory: nil, backUpSaves: { _ in })

        XCTAssertTrue(done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.stagingURL.path), "the partial copy goes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.destination), "a complete one is left to be found")
    }

    func testRecoveryNeverDeletesFromAnotherDriveWithTheSameName() async throws {
        // The move went to drive A. Drive B is now mounted where A was, and
        // has a folder of the same name. B's folder isn't the move's.
        let fake = FakeDrives()
        let driveA = try fake.plugIn("T7", at: root.appendingPathComponent("A"), uuid: "A")
        let driveB = try fake.plugIn("T7", at: root.appendingPathComponent("Drive"), uuid: "B")
        let source = try makeGame()
        let theirs = AppPaths.driveGamesDirectory(onDriveAt: driveB.root).appendingPathComponent("Game")
        try FileManager.default.createDirectory(at: theirs, withIntermediateDirectories: true)
        let record = GameMoveRecord(bottleID: bottleID, source: source.path, sourceDrive: nil,
                                    destination: theirs.path, destinationDrive: driveA.link, stage: .copying)
        var move = mover()
        move.volumes = fake.catalog

        let done = await move.recover(record, bottleDirectory: source, backUpSaves: { _ in })

        XCTAssertTrue(done)
        XCTAssertTrue(FileManager.default.fileExists(atPath: theirs.path))
    }

    func testRecoveryFollowsARenamedDrive() throws {
        let fake = FakeDrives()
        let drive = try fake.plugIn("T7", at: root.appendingPathComponent("T7 1"), uuid: "A")
        let record = GameMoveRecord(
            bottleID: bottleID, source: macGames.appendingPathComponent("Game").path, sourceDrive: nil,
            destination: root.appendingPathComponent("T7/BEER/Games/Game").path,
            destinationDrive: GameDrive(uuid: "A", name: "T7", mountPath: root.appendingPathComponent("T7").path),
            stage: .switched
        )
        var move = mover()
        move.volumes = fake.catalog

        let rebased = move.rebased(record)

        XCTAssertEqual(rebased.destination, AppPaths.driveGamesDirectory(onDriveAt: drive.root).appendingPathComponent("Game").path)
        XCTAssertEqual(rebased.source, record.source, "this Mac doesn't move")
    }

    func testDrivePulledAfterTheSwitchKeepsTheOldCopy() async throws {
        let source = try makeGame()
        let record = record(from: source)

        let outcome = try await mover().run(
            record, cancel: CancelFlag(), progress: { _ in },
            switchBottle: { try FileManager.default.removeItem(at: record.destinationURL) },   // the drive goes
            backUpSaves: { _ in XCTFail("nothing deleted") }
        )

        XCTAssertEqual(outcome, .movedKeptOldCopy(reason: GameMoveStrings.newCopyUnreachable))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("saves/slot1.sav").path))
        XCTAssertEqual(journal.records().first?.stage, .switched, "kept, to finish when the drive is back")
    }

    func testSymlinkedGameFolderIsCopiedNotEmptied() async throws {
        let real = try makeGame()
        let link = macGames.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let copy = root.appendingPathComponent("Copy", isDirectory: true)

        let entries = try FolderCopier.inventory(of: link)
        XCTAssertFalse(entries.isEmpty)
        try FolderCopier.copy(entries, from: link, to: copy, progress: { _ in }, isCancelled: { false })
        XCTAssertNoThrow(try FolderCopier.verify(copy, against: link))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.appendingPathComponent("saves/slot1.sav").path))
    }

    func testJournalKeepsOneMovePerGame() {
        let first = record(from: macGames.appendingPathComponent("Game"))
        var second = first
        second.stage = .switched
        journal.save(first)
        journal.save(second)
        XCTAssertEqual(journal.records(), [second])
        journal.remove(bottleID: bottleID)
        XCTAssertTrue(journal.records().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.url.path))
    }
}

/// Progress updates arrive from the copy's background task.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [GameMoveProgress] = []

    var all: [GameMoveProgress] { lock.withLock { updates } }

    @Sendable func append(_ update: GameMoveProgress) {
        lock.withLock { updates.append(update) }
    }
}
