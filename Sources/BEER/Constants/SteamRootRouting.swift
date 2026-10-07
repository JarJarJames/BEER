import Foundation

/// Maps a Steam cloud "root" token to a relative path under the Wine user home
/// (drive_c/users/<user>/). Steam uses a small, stable set of roots. We accept
/// the token with or without the surrounding %…% the client protocol uses.
let steamRootRouting: [String: String] = [
    "WINSAVEDGAMES": "Saved Games",
    "WINAPPDATAROAMING": "AppData/Roaming",
    "WINAPPDATALOCAL": "AppData/Local",
    "WINAPPDATALOCALLOW": "AppData/LocalLow",
    "WINDOCUMENTS": "Documents",
    "WINMYDOCUMENTS": "Documents",
    "WINMYPICTURES": "Pictures",
    "WINMYMUSIC": "Music",
    "WINMYVIDEO": "Videos",
    "GAMEINSTALL": ""  // resolved specially against the install dir
]
