import Foundation

extension CloudSyncClient {
    struct AchievementInfo: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let displayName: String
        let description: String
        let hidden: Bool
        let icon: String?
        let iconGray: String?
        let unlocked: Bool
        let unlockTime: Date?
    }
}
