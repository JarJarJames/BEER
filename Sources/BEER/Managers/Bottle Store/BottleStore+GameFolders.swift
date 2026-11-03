import AppKit
import Foundation

extension BottleStore {
    /// Give every installed game folder that can be reached its
    /// `.beer-game.json`, so it can be recognized later on its own (after a
    /// move, or on a drive plugged into another Mac). Games from before markers
    /// existed get theirs here, the first time BEER sees them.
    func writeMissingFolderMarkers() {
        for bottle in bottles where bottle.gameInstallStatus == .installed {
            guard let folder = bottle.installLocation(volumes: volumes).url,
                  GameFolderMarkerFile.read(in: folder) == nil else { continue }
            attempt("Write game folder marker", log: Log.install) {
                try GameFolderMarkerFile.write(GameFolderMarkerFile.marker(for: bottle, installDir: folder), in: folder)
            }
        }
    }

    /// Where `bottle`'s game is right now. For views: cheap enough to call
    /// from `body` (a stat, plus a drive lookup only when that fails).
    func installLocation(of bottle: Bottle) -> InstallLocation {
        bottle.installLocation(volumes: volumes)
    }

    /// Show the game's own folder in Finder, which for a game on a drive isn't
    /// inside the bottle.
    func revealGameFiles(_ bottle: Bottle) {
        guard let folder = installLocation(of: bottle).url else { return reveal(bottle) }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
