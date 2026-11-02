import Foundation

/// What the free-space check found before a game or DLC install.
enum InstallSpace: Equatable {
    case fits
    /// Steam gave no size, so the install goes ahead; the note says why.
    case unchecked(String)
    case short(DiskSpaceShortfall)
}

/// Asks Steam how big a game (or a batch of its DLC) is and whether the disk
/// can hold it, before anything is downloaded. Both lookups are swappable so
/// tests can fake a full disk and Steam's answer.
struct InstallSpaceCheck {
    var client = CloudSyncClient()
    var freeSpace: @Sendable (URL) -> (bytes: Int64, name: String)? = DiskSpaceCheck.freeSpace(at:)

    /// `destination` is where the files will go. `partialDownload` is a folder
    /// an earlier, unfinished download of the same content left behind; only
    /// the rest still needs room. Never pass a game's folder for its DLC: the
    /// base game in it isn't part of the DLC.
    func run(appIDs: [Int], account: SteamCloudAccount, destination: URL, partialDownload: URL? = nil) async -> InstallSpace {
        let installBytes: Int64?
        do {
            installBytes = try await client.installSize(
                appIDs: appIDs, account: account.accountName, refreshToken: account.refreshToken
            )
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .unchecked(DiskSpaceStrings.sizeCheckFailed(msg))
        }
        guard let installBytes else { return .unchecked(DiskSpaceStrings.unknownSize) }

        let freeSpace = freeSpace
        let shortfall = await Task.detached { () -> DiskSpaceShortfall? in
            // An unreadable volume is left to the download to hit.
            guard let volume = freeSpace(destination) else { return nil }
            return DiskSpaceCheck.shortfall(
                installBytes: installBytes,
                alreadyOnDisk: partialDownload.map(DiskSpaceCheck.allocatedSize(of:)) ?? 0,
                availableBytes: volume.bytes,
                volumeName: volume.name
            )
        }.value
        return shortfall.map(InstallSpace.short) ?? .fits
    }
}
