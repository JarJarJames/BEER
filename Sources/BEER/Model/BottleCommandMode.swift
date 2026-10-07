import AppKit
import Foundation

enum BottleCommandMode {
    case wineboot
    case winebootKill
    case wine(arguments: [String])
    /// A runtime helper binary invoked directly (e.g. `wineserver -w`).
    case executable(path: String, arguments: [String])
}
