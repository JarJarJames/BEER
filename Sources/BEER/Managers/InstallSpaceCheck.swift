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

/// Steam's answer to "how big is this?".
struct InstallSize: Equatable {
    let bytes: Int64?
    /// Why free space can't be checked (Steam lists no size, or couldn't be
    /// asked); nil when `bytes` is known.
    let uncheckedReason: String?
    /// Owned DLC that come down with the game, which the user can leave out.
    var dlc: [InstallableDLC] = []
    /// Every depot the whole download fetches; empty when Steam didn't say.
    var depotIDs: [Int] = []

    /// The size without the DLC in `skipped`.
    func leavingOut(_ skipped: Set<Int>) -> InstallSize {
        let saved = dlc.filter { skipped.contains($0.appID) }.compactMap(\.bytes).reduce(0, +)
        return InstallSize(bytes: bytes.map { max($0 - saved, 0) }, uncheckedReason: uncheckedReason,
                           dlc: dlc, depotIDs: depotIDs)
    }

    /// The depots to hand DepotDownloader with `-depot` so it skips `leftOut`.
    /// Nil when nothing is left out (or Steam didn't list the depots), so it
    /// picks the depots itself, as it always has.
    func depots(leavingOut leftOut: [InstallableDLC]) -> [Int]? {
        let skipped = Set(leftOut.flatMap(\.depotIDs))
        guard !skipped.isEmpty, !depotIDs.isEmpty else { return nil }
        return depotIDs.filter { !skipped.contains($0) }
    }
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
        await assess(size(appIDs: appIDs, account: account), destination: destination, partialDownload: partialDownload)
    }

    /// Steam's size for the install. Asked once per sheet: choosing another
    /// drive only re-runs `assess`.
    func size(appIDs: [Int], account: SteamCloudAccount) async -> InstallSize {
        do {
            let contents = try await client.installSize(
                appIDs: appIDs, account: account.accountName, refreshToken: account.refreshToken
            )
            return InstallSize(bytes: contents.bytes,
                               uncheckedReason: contents.bytes == nil ? DiskSpaceStrings.unknownSize : nil,
                               dlc: contents.dlc, depotIDs: contents.depotIDs)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return InstallSize(bytes: nil, uncheckedReason: DiskSpaceStrings.sizeCheckFailed(msg))
        }
    }

    /// Whether `size` fits at `destination`.
    func assess(_ size: InstallSize, destination: URL, partialDownload: URL? = nil) async -> InstallSpaceReport {
        let freeSpace = freeSpace
        let (volume, alreadyOnDisk) = await Task.detached {
            (freeSpace(destination), partialDownload.map(DiskSpaceCheck.allocatedSize(of:)) ?? 0)
        }.value

        let verdict: InstallSpace
        if let unchecked = size.uncheckedReason {
            verdict = .unchecked(unchecked)
        } else if let installBytes = size.bytes, let volume, let shortfall = DiskSpaceCheck.shortfall(
            installBytes: installBytes, alreadyOnDisk: alreadyOnDisk,
            availableBytes: volume.availableBytes, volumeName: volume.name
        ) {
            verdict = .short(shortfall)
        } else {
            // Fits, or the volume couldn't be read: that's left to the download to hit.
            verdict = .fits
        }
        return InstallSpaceReport(installBytes: size.bytes, volume: volume, verdict: verdict)
    }
}
