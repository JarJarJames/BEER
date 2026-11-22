import Foundation

/// How much of a download has come down, read from the disk while
/// DepotDownloader runs.
///
/// DepotDownloader prints a percentage only when a whole file is done, so a
/// game made of a few multi-GB files (Deus Ex's BIGFILEs) sat on one number
/// for minutes. It pre-allocates each file with `SetLength`, which on a volume
/// with sparse files (APFS) takes no space until data lands, so the space the
/// game's folder takes is how much has arrived.
enum DownloadedBytes {
    /// How often a running download's folder is measured.
    static let interval: Duration = .seconds(2)

    /// The bytes `folder` takes on disk. Nil on a volume without sparse files
    /// (exFAT, FAT32), where a pre-allocated file takes its full size at once.
    static func measure(_ folder: URL) -> Int64? {
        let sparse = try? folder.resourceValues(forKeys: [.volumeSupportsSparseFilesKey]).volumeSupportsSparseFiles
        guard sparse == true else { return nil }
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            return nil
        }
        var total: Int64 = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// The whole download's size: every depot in `depots`, or every sized one
    /// when DepotDownloader picks the depots itself. Nil when one of `depots`
    /// has no size, so the bar can't run ahead of the download.
    static func total(of depots: [Int]?, sizes: [Int: Int64]) -> Int64? {
        let listed = depots.map { ids in ids.map { sizes[$0] } } ?? sizes.values.map(Optional.some)
        guard !listed.isEmpty, !listed.contains(nil) else { return nil }
        let total = listed.compactMap { $0 }.reduce(0, +)
        return total > 0 ? total : nil
    }

    /// The download's fraction from `bytes` of `total`, held below 1: only
    /// DepotDownloader's own "done" finishes the bar.
    static func fraction(_ bytes: Int64, of total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(0.99, Double(bytes) / Double(total))
    }
}
