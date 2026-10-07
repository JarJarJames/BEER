import CryptoKit
import Foundation

enum SHA1Digest {
    /// SteamKit versions have exposed the cloud SHA-1 as either Base64 or hex.
    /// Accept both representations so helper upgrades cannot cause every file
    /// to be treated as changed.
    static func fileMatches(_ url: URL, remoteDigest: String) -> Bool {
        guard !remoteDigest.isEmpty,
              let digest = try? fileDigest(url)
        else { return false }

        if remoteDigest == Data(digest).base64EncodedString() {
            return true
        }
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return remoteDigest.caseInsensitiveCompare(hex) == .orderedSame
    }

    private static func fileDigest(_ url: URL) throws -> Insecure.SHA1.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = Insecure.SHA1()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize()
    }
}
