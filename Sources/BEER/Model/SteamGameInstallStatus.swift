import Foundation

enum SteamGameInstallStatus: String, Codable {
    case notInstalled
    case queued
    case installing
    case installed
    case updateAvailable
    case failed
}
