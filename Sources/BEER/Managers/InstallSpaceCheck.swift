import Foundation

/// What the free-space check found before a game or DLC install.
enum InstallSpace: Equatable {
    case fits
    /// Steam gave no size, so the install goes ahead; the note says why.
    case unchecked(String)
    case short(DiskSpaceShortfall)
}

/// Free space on the volume an install goes to.
struct VolumeSpace: Equatable {
    let availableBytes: Int64
    let name: String
}

/// The check's result with the numbers the install sheet shows.
struct InstallSpaceReport: Equatable {
    /// Steam's size for the install; nil when Steam lists none or couldn't be asked.
    let installBytes: Int64?
    /// Nil when the volume couldn't be read.
    let volume: VolumeSpace?
    let verdict: InstallSpace
}

/// Asks Steam how big a game (or a batch of its DLC) is and whether the disk
/// can hold it, before anything is downloaded. Both lookups are swappable so
/// tests can fake a full disk and Steam's answer.
struct InstallSpaceCheck {
    var client = CloudSyncClient()
    var freeSpace: @Sendable (URL) -> VolumeSpace? = DiskSpaceCheck.freeSpace(at:)

    /// `destination` is where the files will go. `partialDownload` is a folder
    /// an earlier, unfinished download of the same content left behind; only
    /// the rest still needs room. Never pass a game's folder for its DLC: the
    /// base game in it isn't part of the DLC.
    func run(appIDs: [Int], account: SteamCloudAccount, destination: URL, partialDownload: URL? = nil) async -> InstallSpace {
        await report(appIDs: appIDs, account: account, destination: destination, partialDownload: partialDownload).verdict
    }

    func report(appIDs: [Int], account: SteamCloudAccount, destination: URL, partialDownload: URL? = nil) async -> InstallSpaceReport {
        let installBytes: Int64?
        var unchecked: String?
        do {
            installBytes = try await client.installSize(
                appIDs: appIDs, account: account.accountName, refreshToken: account.refreshToken
            )
            if installBytes == nil { unchecked = DiskSpaceStrings.unknownSize }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            installBytes = nil
            unchecked = DiskSpaceStrings.sizeCheckFailed(msg)
        }

        let freeSpace = freeSpace
        let (volume, alreadyOnDisk) = await Task.detached {
            (freeSpace(destination), partialDownload.map(DiskSpaceCheck.allocatedSize(of:)) ?? 0)
        }.value

        let verdict: InstallSpace
        if let unchecked {
            verdict = .unchecked(unchecked)
        } else if let installBytes, let volume, let shortfall = DiskSpaceCheck.shortfall(
            installBytes: installBytes, alreadyOnDisk: alreadyOnDisk,
            availableBytes: volume.availableBytes, volumeName: volume.name
        ) {
            verdict = .short(shortfall)
        } else {
            // Fits, or the volume couldn't be read: that's left to the download to hit.
            verdict = .fits
        }
        return InstallSpaceReport(installBytes: installBytes, volume: volume, verdict: verdict)
    }
}
