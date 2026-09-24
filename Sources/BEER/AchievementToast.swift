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

/// Minimal "Achievement Unlocked" toast, mounted once at the app root
/// (BEERApp.swift). Kept deliberately simple for this first pass — no
/// settings screen yet to configure position/sound (see CLAUDE.md plan).
struct AchievementToastOverlay: View {
    @ObservedObject private var center = AchievementToastCenter.shared

    var body: some View {
        VStack {
            if let achievement = center.current {
                HStack(spacing: 12) {
                    AsyncImage(url: achievement.icon.flatMap(URL.init)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Achievement Unlocked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(achievement.displayName)
                            .font(.headline)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: 320)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(achievement.name)
            }
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: center.current)
        .allowsHitTesting(false)
    }
}
