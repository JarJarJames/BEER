import Foundation

/// What the free-space check found before a game install.
enum InstallSpace: Equatable {
    case fits
    /// Steam gave no size, so the install goes ahead; the note says why.
    case unchecked(String)
    case short(DiskSpaceShortfall)
}

/// Asks Steam how big a game is and whether the disk can hold it, before
/// anything is downloaded. Both lookups are swappable so tests can fake a
/// full disk and Steam's answer.
struct InstallSpaceCheck {
    var client = CloudSyncClient()
    var freeSpace: @Sendable (URL) -> (bytes: Int64, name: String)? = DiskSpaceCheck.freeSpace(at:)

    /// `installDir` is the game's folder when a bottle already exists for it:
    /// a download that stopped partway left files there.
    func run(appID: Int, account: SteamCloudAccount, installDir: URL?) async -> InstallSpace {
        let installBytes: Int64?
        do {
            installBytes = try await client.installSize(
                appID: appID, account: account.accountName, refreshToken: account.refreshToken
            )
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .unchecked(DiskSpaceStrings.sizeCheckFailed(msg))
        }
        guard let installBytes else { return .unchecked(DiskSpaceStrings.unknownSize) }

        let freeSpace = freeSpace
        let shortfall = await Task.detached { () -> DiskSpaceShortfall? in
            // An unreadable volume is left to the download to hit.
            guard let volume = freeSpace(installDir ?? AppPaths.bottlesDirectory) else { return nil }
            return DiskSpaceCheck.shortfall(
                installBytes: installBytes,
                alreadyOnDisk: installDir.map(DiskSpaceCheck.allocatedSize(of:)) ?? 0,
                availableBytes: volume.bytes,
                volumeName: volume.name
            )
        }.value
        return shortfall.map(InstallSpace.short) ?? .fits
    }
}
