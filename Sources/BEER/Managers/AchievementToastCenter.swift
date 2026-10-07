import AchievementUI
import AppKit
import Combine
import SwiftUI

/// A tiny event bus for "an achievement just unlocked" toasts. One shared
/// instance so any `AchievementWatcher` (there is one per running game) can
/// post to it without needing a view hierarchy reference.
@MainActor
final class AchievementToastCenter: ObservableObject {
    static let shared = AchievementToastCenter()

    @Published private(set) var current: AchievementDisplayInfo?
    private var queue: [AchievementDisplayInfo] = []
    private var dismissTask: Task<Void, Never>?

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
