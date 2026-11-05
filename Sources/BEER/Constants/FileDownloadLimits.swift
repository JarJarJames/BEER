import Foundation

/// How often `FileDownload` reports progress, so a big download updates the
/// screen smoothly without flooding it.
enum FileDownloadLimits {
    /// Reports per download when the server says how big it is (one per percent).
    static let progressSteps: Int64 = 100
    /// Bytes between reports when the server doesn't say how big it is.
    static let unknownSizeStepBytes: Int64 = 1024 * 1024
}
