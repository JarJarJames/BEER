import Foundation

/// Reads and writes the `.beer-game.json` file in a game folder.
enum GameFolderMarkerFile {
    static func url(in folder: URL) -> URL {
        folder.appendingPathComponent(GameFolderMarker.fileName, isDirectory: false)
    }

    /// Nil when the folder has none, or one this build can't read.
    static func read(in folder: URL) -> GameFolderMarker? {
        // No file is the common case for folders from before markers existed.
        guard let data = try? Data(contentsOf: url(in: folder)) else { return nil }
        return try? JSONDecoder.gamenative.decode(GameFolderMarker.self, from: data)
    }

    static func write(_ marker: GameFolderMarker, in folder: URL) throws {
        let data = try JSONEncoder.gamenative.encode(marker)
        try data.write(to: url(in: folder), options: .atomic)
    }

    /// What the folder at `installDir` holds, from the bottle that uses it.
    static func marker(for bottle: Bottle, installDir: URL) -> GameFolderMarker {
        GameFolderMarker(
            appID: bottle.steamAppID,
            name: bottle.steamGameName ?? bottle.name,
            isNonSteam: bottle.steamAppID == nil,
            launchExecutable: bottle.gameLaunchExecutable.flatMap {
                relativePath(of: URL(fileURLWithPath: $0), in: installDir)
            }
        )
    }

    static func relativePath(of file: URL, in folder: URL) -> String? {
        let root = GameFolders.canonicalPath(folder)
        let path = GameFolders.canonicalPath(file)
        guard path.hasPrefix(root + "/") else { return nil }
        return String(path.dropFirst(root.count + 1))
    }
}
