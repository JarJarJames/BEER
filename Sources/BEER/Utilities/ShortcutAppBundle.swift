import Foundation

/// The small `.app` a game shortcut is: a script that opens the game's
/// `beer://` link, the game's icon, and an Info.plist naming the game so BEER
/// can tell its own shortcuts from anything else with the same name.
enum ShortcutAppBundle {
    /// Info.plist key holding the game's app ID.
    static let appIDKey = "BEERGameAppID"
    private static let executableName = "launch"
    private static let iconName = "AppIcon"

    /// A game name as a Finder name: no `/`, and `:` (which Finder shows as
    /// `/`) spelled as a dash.
    static func fileName(for gameName: String) -> String {
        let cleaned = gameName
            .replacingOccurrences(of: ":", with: " -")
            .replacingOccurrences(of: "/", with: "-")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return (cleaned.isEmpty ? "Game" : cleaned) + ".app"
    }

    /// The game a shortcut opens, or nil when `url` isn't a BEER shortcut.
    static func appID(at url: URL) -> Int? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (info[appIDKey] as? NSNumber)?.intValue
    }

    /// Write the shortcut at `url`. A shortcut BEER made for the same game is
    /// replaced; anything else already there is left alone and is an error.
    static func write(at url: URL, gameName: String, appID: Int, icns: Data) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            guard Self.appID(at: url) == appID else { throw GameShortcutError.nameTaken(url.lastPathComponent) }
            try fm.removeItem(at: url)
        }
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleExecutable": executableName,
            "CFBundleIdentifier": "io.github.jarjarjames.beer.shortcut.\(appID)",
            "CFBundleName": gameName,
            "CFBundleDisplayName": gameName,
            "CFBundleIconFile": iconName,
            "CFBundlePackageType": "APPL",
            "LSMinimumSystemVersion": "14.0",
            // It only hands the link to BEER and exits, so it never needs a Dock icon of its own.
            "LSUIElement": true,
            appIDKey: appID,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        let script = macOS.appendingPathComponent(executableName)
        try "#!/bin/sh\nexec /usr/bin/open \"\(GameShortcutLink(appID: appID).url.absoluteString)\"\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        try icns.write(to: resources.appendingPathComponent("\(iconName).icns"))
    }

    /// Replace just the icon of a shortcut already written.
    static func replaceIcon(at url: URL, icns: Data) throws {
        try icns.write(to: url.appendingPathComponent("Contents/Resources/\(iconName).icns"))
    }
}
