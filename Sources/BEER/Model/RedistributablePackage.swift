import Foundation

/// One Microsoft redistributable: where it comes from, what it must hash to,
/// and how to run it unattended inside Wine.
struct RedistributablePackage: Equatable, Sendable {
    /// Hosts we accept downloads from. Anything else is refused before a
    /// request is made, so a bad manifest edit can't point at a mirror.
    static let officialHosts: Set<String> = [
        "download.microsoft.com",
        "download.visualstudio.microsoft.com",
    ]

    let fileName: String
    let url: URL
    /// Lowercase hex SHA-256 of the file.
    let sha256: String
    let size: Int64
    let installArguments: [String]
    /// Windows exit codes that mean "installed": success, success-but-reboot
    /// (3010), and "a newer version is already installed" (1638).
    let successExitCodes: Set<Int32>

    var isFromOfficialHost: Bool {
        url.scheme == "https" && url.host.map(Self.officialHosts.contains) == true
    }

    /// Wine hands the Windows exit code back as a Unix status, which keeps
    /// only the low byte — so 3010 reaches us as 194. Accept either form.
    func isSuccess(exitCode: Int32) -> Bool {
        successExitCodes.contains(exitCode)
            || successExitCodes.contains { $0 & 0xFF == exitCode }
    }
}
