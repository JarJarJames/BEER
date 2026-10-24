import Foundation

/// User-facing text for the Dependencies row and its installer.
enum WindowsDependencyStrings {
    static let rowTitle = "Dependencies"
    static let install = "Install"
    static let reinstall = "Reinstall"
    static let installed = "Installed"
    static let caption = "Microsoft runtimes some games need but don't install themselves. Downloaded from Microsoft, checked against a pinned SHA-256, then run silently in this bottle. Quit the game first."

    static func title(for dependency: WindowsDependency) -> String {
        switch dependency {
        case .vcRedist: "Visual C++ 2015–2026"
        case .directX: "DirectX (June 2010)"
        }
    }

    static func detail(for dependency: WindowsDependency) -> String {
        switch dependency {
        case .vcRedist: "x86 + x64 runtime (msvcp140, vcruntime140). Fixes \"VCRUNTIME140.dll was not found\"."
        case .directX: "Legacy d3dx9/10/11, XAudio2, XACT and XInput 1.3 libraries."
        }
    }

    static func downloading(_ file: String, size: Int64) -> String { "Downloading \(file) (\(size.fileSizeString))…" }
    static func verifying(_ file: String) -> String { "Verifying \(file)…" }
    static func running(_ file: String) -> String { "Running \(file)…" }
    static func finished(_ dependency: WindowsDependency) -> String { "\(dependency.title) installed." }
    static let preparing = "Preparing the bottle…"
    static let applyingOverrides = "Setting DLL overrides…"
    static let failed = "Install failed."
}
