import AppKit
import Foundation

/// The drives plugged in right now, kept current as drives are connected,
/// ejected or renamed, so drive lists and "Connect <drive> to play" update the
/// moment it happens instead of on the next click.
@MainActor @Observable
final class InstallVolumeMonitor {
    /// Every mounted drive other than the startup disk, listed or not.
    private(set) var drives: [InstallVolume] = []

    /// Drive lookups that answer from the list above instead of asking the
    /// system each time: views ask on every redraw. Paths are still checked
    /// live, so a drive pulled a moment ago never reads as holding a game.
    /// A view that looks a drive up through these redraws when the list
    /// changes, as if it had read `drives` itself.
    @ObservationIgnored private(set) var current: VolumeCatalog = .system

    private let source: VolumeCatalog
    private let snapshot: DriveSnapshot
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(source: VolumeCatalog = .system) {
        let snapshot = DriveSnapshot()
        self.source = source
        self.snapshot = snapshot
        current = VolumeCatalog(mountedDrives: { [weak self] in
            if Thread.isMainThread { MainActor.assumeIsolated { _ = self?.drives } }
            return snapshot.drives
        }, volumeUUID: source.volumeUUID)
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // Read on this thread: `Notification` isn't Sendable.
                let info = note.userInfo
                let current = info?[NSWorkspace.volumeURLUserInfoKey] as? URL
                let old = info?[NSWorkspace.oldVolumeURLUserInfoKey] as? URL
                let name = info?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String
                let isUnmount = note.name == NSWorkspace.didUnmountNotification
                MainActor.assumeIsolated {
                    self?.refresh(mountedAt: isUnmount ? nil : current, named: name, gone: isUnmount ? current : old)
                }
            }
        }
        refresh()
    }

    /// Read the drive list again. A notification's own addresses override
    /// the system's list, which lags behind it: right after a rename the
    /// list still names the old path, which no longer exists, so the drive
    /// would read as unplugged and nothing would come along to fix that.
    /// The drive also reports its old name for a moment, hence `name`.
    func refresh(mountedAt mounted: URL? = nil, named name: String? = nil, gone: URL? = nil) {
        let goneRoot = gone.map(GameFolders.canonicalPath)
        var fresh = source.mountedDrives().filter { GameFolders.canonicalPath($0.root) != goneRoot }
        if let mounted, var drive = source.drive(mounted) {
            if let name { drive = drive.named(name) }
            fresh.removeAll { $0.id == drive.id }
            fresh.append(drive)
        }
        snapshot.drives = fresh
        if fresh != drives { drives = fresh }
    }
}

/// The last drive list, readable from any thread.
private final class DriveSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [InstallVolume] = []

    var drives: [InstallVolume] {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
