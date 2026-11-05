import Foundation

/// How much of a download has arrived, for a progress bar.
struct ByteProgress: Equatable {
    let received: Int64
    /// 0 when the size isn't known.
    let expected: Int64

    var fraction: Double {
        expected > 0 ? min(Double(received) / Double(expected), 1) : 0
    }
}
