import Foundation

struct AchievementFetchOutcome {
    let achievements: [CloudSyncClient.AchievementInfo]
    /// Always non-nil, even on success — this is the only place that
    /// reports whether achievements were actually seeded, since the fetch
    /// itself is silent otherwise and a failure here has no other symptom
    /// than achievements quietly never unlocking.
    let note: String
}
