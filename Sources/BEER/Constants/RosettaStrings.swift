import Foundation

/// User-facing text for installing Rosetta, which Wine needs to run.
enum RosettaStrings {
    static let title = "Install Rosetta?"
    static let message = "BEER runs Windows games with Wine, which needs Apple's Rosetta. It's free, installs once, and macOS will ask for your password. Try again once it's installed."
    static let install = "Install Rosetta"
    static let notNow = "Not Now"
    static let installTerminalCommand = "softwareupdate --install-rosetta --agree-to-license"
    static func installFailed(_ detail: String) -> String {
        let reason = detail.isEmpty ? "" : " (\(detail))"
        return "Couldn't install Rosetta\(reason). Install it from Terminal with: \(installTerminalCommand)"
    }
}
