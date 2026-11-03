import AppKit
import Combine
import Foundation

/// The drives plugged in right now, kept current as drives are connected,
/// ejected or renamed, so drive lists and "Connect <drive> to play" update the
/// moment it happens instead of on the next click.
@MainActor
final class InstallVolumeMonitor: ObservableObject {
    /// Every mounted drive other than the startup disk, listed or not.
    @Published private(set) var drives: [InstallVolume] = []

    /// Drive lookups that answer from the list above instead of asking the
    /// system each time: views ask on every redraw. Paths are still checked
    /// live, so a drive pulled a moment ago never reads as holding a game.
    let current: VolumeCatalog

    private let source: VolumeCatalog
    private let snapshot: DriveSnapshot
    private var observers: [NSObjectProtocol] = []

    init(source: VolumeCatalog = .system) {
        let snapshot = DriveSnapshot()
        self.source = source
        self.snapshot = snapshot
        current = VolumeCatalog(mountedDrives: { snapshot.drives }, volumeUUID: source.volumeUUID)
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        let fresh = source.mountedDrives()
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
