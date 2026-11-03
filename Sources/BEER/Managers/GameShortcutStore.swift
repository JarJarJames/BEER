import AppKit
import CoreServices
import Foundation

/// Makes desktop and application shortcuts for games, updates their icons,
/// and removes them on uninstall. Remembers what it made in
/// `shortcuts.json`; a shortcut the player moved or renamed is theirs and is
/// never touched.
@MainActor
final class GameShortcutStore {
    static let shared = GameShortcutStore()

    struct Locations {
        var desktop: URL
        var applications: URL
        var records: URL

        static var live: Locations {
            Locations(
                desktop: AppPaths.desktopDirectory,
                applications: AppPaths.applicationShortcutsDirectory,
                records: AppPaths.gameShortcutsURL
            )
        }

        func directory(for kind: GameShortcutKind) -> URL {
            switch kind {
            case .desktop: desktop
            case .application: applications
            }
        }
    }

    let locations: Locations
    /// Reads artwork. Swappable so tests don't need the network.
    var fetch: @Sendable (URL) async throws -> Data = GameShortcutStore.download
    /// Tells Finder and the Dock a shortcut changed. Swappable so tests don't
    /// register throwaway apps with Launch Services.
    var announce: (URL) -> Void = GameShortcutStore.announceToFinder
    private(set) var records: [GameShortcutRecord]

    init(locations: Locations = .live) {
        self.locations = locations
        let data = try? Data(contentsOf: locations.records)
        records = data.flatMap { try? JSONDecoder().decode([GameShortcutRecord].self, from: $0) } ?? []
    }

    /// Make (or remake) one kind of shortcut for `game`, with its chosen icon.
    @discardableResult
    func create(_ kind: GameShortcutKind, for game: SteamLibraryGame) async throws -> URL {
        let icns = try await icns(for: game)
        let directory = locations.directory(for: kind)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(ShortcutAppBundle.fileName(for: game.name), isDirectory: true)
        try ShortcutAppBundle.write(at: url, gameName: game.name, appID: game.appID, icns: icns)
        announce(url)

        records.removeAll { $0.appID == game.appID && $0.kind == kind }
        records.append(GameShortcutRecord(appID: game.appID, kind: kind, path: url.path))
        save()
        return url
    }

    /// Give `game`'s existing shortcuts its current icon.
    func updateIcons(for game: SteamLibraryGame) async throws {
        let shortcuts = ownShortcuts(appID: game.appID)
        guard !shortcuts.isEmpty else { return }
        let icns = try await icns(for: game)
        for url in shortcuts {
            try ShortcutAppBundle.replaceIcon(at: url, icns: icns)
            announce(url)
        }
    }

    /// Remove the shortcuts BEER made for a game that's being uninstalled.
    func removeShortcuts(appID: Int) {
        for url in ownShortcuts(appID: appID) {
            try? FileManager.default.removeItem(at: url)
        }
        records.removeAll { $0.appID == appID }
        save()
    }

    /// The shortcuts still where BEER put them and still opening this game.
    private func ownShortcuts(appID: Int) -> [URL] {
        records
            .filter { $0.appID == appID }
            .map { URL(fileURLWithPath: $0.path, isDirectory: true) }
            .filter { ShortcutAppBundle.appID(at: $0) == appID }
    }

    /// The icon `game`'s shortcuts show: Steam's icon when picked and big
    /// enough, otherwise the picked (or centred) square of the cover.
    func iconImage(for game: SteamLibraryGame) async throws -> CGImage {
        let choice = game.shortcutIcon ?? .default
        if choice == .steamIcon,
           let url = game.clientIconURL.flatMap(URL.init(string:)),
           let image = ShortcutIconImage.steamIcon(from: try await fetch(url)) {
            return image
        }
        guard let coverURL = game.shortcutCoverImage else { throw GameShortcutError.noArtwork }
        guard let cover = ShortcutIconImage.image(from: try await fetch(coverURL)) else {
            throw GameShortcutError.artworkUnreadable
        }
        let crop: CoverCrop = if case .cover(let c) = choice { c } else { .centered }
        guard let square = ShortcutIconImage.crop(cover, to: crop) else { throw GameShortcutError.artworkUnreadable }
        return square
    }

    private func icns(for game: SteamLibraryGame) async throws -> Data {
        guard let icns = ShortcutIconImage.icns(from: try await iconImage(for: game)) else {
            throw GameShortcutError.artworkUnreadable
        }
        return icns
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: locations.records.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(records).write(to: locations.records, options: .atomic)
        } catch {
            NSLog("BEER: couldn't save shortcuts list: \(error.localizedDescription)")
        }
    }

    nonisolated static func download(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GameShortcutError.artworkUnreadable
        }
        return data
    }

    /// Finder and the Dock cache app icons; touching the bundle and
    /// re-registering it makes them show the new one.
    nonisolated private static func announceToFinder(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        LSRegisterURL(url as CFURL, true)
        NSWorkspace.shared.noteFileSystemChanged(url.path)
    }
}
