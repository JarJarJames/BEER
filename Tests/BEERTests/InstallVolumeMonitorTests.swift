import XCTest
@testable import BEER

/// The drive list after a drive is renamed or pulled. macOS sends the
/// notification while its own list of mounted drives still shows the old
/// state (seen live: right after a rename the list still names the old path,
/// which can no longer be read), so the monitor goes by the notification's
/// addresses. Drives are faked; nothing here touches a real disk.
@MainActor
final class InstallVolumeMonitorTests: XCTestCase {
    private let oldRoot = URL(fileURLWithPath: "/Volumes/BEERTestingAparatus", isDirectory: true)
    private let newRoot = URL(fileURLWithPath: "/Volumes/BEERTestingAparatus2", isDirectory: true)

    private func drive(at root: URL, name: String) -> InstallVolume {
        InstallVolume(root: root, name: name, uuid: "831E0E1D", availableBytes: 100, format: "APFS",
                      supportsSymbolicLinks: true, isCaseSensitive: false, isReadOnly: false,
                      isLocal: true, isDiskImage: false)
    }

    func testRenamedDriveStaysConnected() {
        let renamed = drive(at: newRoot, name: "BEERTestingAparatus2")
        let newRoot = newRoot
        // The system list still has only the old path, which fails to read.
        let monitor = InstallVolumeMonitor(source: VolumeCatalog(
            mountedDrives: { [] }, volumeUUID: { _ in nil },
            drive: { $0 == newRoot ? renamed : nil }
        ))

        monitor.refresh(mountedAt: newRoot, gone: oldRoot)

        XCTAssertEqual(monitor.drives, [renamed])
        XCTAssertEqual(monitor.current.drive(withUUID: "831E0E1D"), renamed)
    }

    func testGameFollowsTheRenameThroughTheMonitor() {
        // Read right after the rename, the drive still gives its old name.
        let renamed = drive(at: newRoot, name: "BEERTestingAparatus")
        let newRoot = newRoot
        let monitor = InstallVolumeMonitor(source: VolumeCatalog(
            mountedDrives: { [] }, volumeUUID: { _ in nil },
            drive: { $0 == newRoot ? renamed : nil }
        ))
        var bottle = FakeDrives.bottle()
        bottle.gameInstallDirectory = oldRoot.appendingPathComponent("BEER/Games/Easy Delivery Co").path
        bottle.gameLaunchExecutable = oldRoot.appendingPathComponent("BEER/Games/Easy Delivery Co/EasyDeliveryCo.exe").path
        bottle.gameDrive = GameDrive(uuid: "831E0E1D", name: "BEERTestingAparatus", mountPath: oldRoot.path)

        monitor.refresh(mountedAt: newRoot, named: "BEERTestingAparatus2", gone: oldRoot)

        XCTAssertTrue(bottle.followRenamedDrive(volumes: monitor.current))
        XCTAssertEqual(bottle.gameInstallDirectory, "/Volumes/BEERTestingAparatus2/BEER/Games/Easy Delivery Co")
        XCTAssertEqual(bottle.gameLaunchExecutable, "/Volumes/BEERTestingAparatus2/BEER/Games/Easy Delivery Co/EasyDeliveryCo.exe")
        XCTAssertEqual(bottle.gameDrive?.name, "BEERTestingAparatus2")
    }

    func testPulledDriveIsGoneEvenWhileTheListLags() {
        // The system list still shows the drive just pulled.
        let pulled = drive(at: oldRoot, name: "BEERTestingAparatus")
        let monitor = InstallVolumeMonitor(source: VolumeCatalog(
            mountedDrives: { [pulled] }, volumeUUID: { _ in nil }
        ))
        monitor.refresh()
        XCTAssertEqual(monitor.drives, [pulled])

        monitor.refresh(gone: oldRoot)

        XCTAssertEqual(monitor.drives, [])
        XCTAssertNil(monitor.current.drive(withUUID: "831E0E1D"))
    }

    func testPluggedInDriveShowsUpBeforeTheListHasIt() {
        let plugged = drive(at: oldRoot, name: "BEERTestingAparatus")
        let oldRoot = oldRoot
        let monitor = InstallVolumeMonitor(source: VolumeCatalog(
            mountedDrives: { [] }, volumeUUID: { _ in nil },
            drive: { $0 == oldRoot ? plugged : nil }
        ))

        monitor.refresh(mountedAt: oldRoot)

        XCTAssertEqual(monitor.drives, [plugged])
    }
}
