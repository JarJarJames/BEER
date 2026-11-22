import AchievementUI
import AppKit
import SwiftUI

/// A tiny event bus for "an achievement just unlocked" toasts. One shared
/// instance so any `AchievementWatcher` (there is one per running game) can
/// post to it without needing a view hierarchy reference.
@MainActor @Observable
final class AchievementToastCenter {
    static let shared = AchievementToastCenter()

    private(set) var current: AchievementDisplayInfo?
    @ObservationIgnored private var queue: [AchievementDisplayInfo] = []
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func post(_ achievements: [AchievementDisplayInfo]) {
        queue.append(contentsOf: achievements)
        advanceIfNeeded()
    }

    private func advanceIfNeeded() {
        guard current == nil, !queue.isEmpty else { return }
        current = queue.removeFirst()
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            self?.current = nil
            self?.advanceIfNeeded()
        }
    }
}
