import Foundation

/// UserDefaults keys for where installs go.
enum InstallPreferences {
    /// The drive the last install went to, offered first next time. Absent
    /// when that was this Mac.
    static let lastDriveKey = "install.lastDriveUUID"
}
