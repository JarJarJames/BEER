import Foundation

/// The runtime the Runtime Manager marks "Recommended for this Mac": one
/// already installed, or a catalog release still to download.
enum RuntimeRecommendation: Equatable {
    case installed(RuntimeCandidate)
    case release(RuntimeRelease)
}
