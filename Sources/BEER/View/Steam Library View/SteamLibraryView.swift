import SwiftUI

struct SteamLibraryGridView: View {
    var onSelectGame: (SteamLibraryGame) -> Void
    /// When true, show only installed games (the "Installed" sidebar tab).
    var installedOnly: Bool = false

    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var bottles: BottleStore
    @EnvironmentObject private var auth: SteamAuthStore
    @State private var searchText: String = ""

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 18, alignment: .top)
    ]

    private func isInstalled(_ game: SteamLibraryGame) -> Bool {
        guard let bottleID = game.installedBottleID else { return false }
        return bottles.bottles.contains { $0.id == bottleID }
    }

    private var filteredGames: [SteamLibraryGame] {
        var base = installedOnly ? library.games.filter(isInstalled) : library.games

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            base = base.filter { $0.name.lowercased().contains(q) || String($0.appID).contains(q) }
        }

        // Installed games first, then alphabetical — so the handful you've
        // installed are always at the top of a 300-game library.
        return base.sorted { a, b in
            let ai = isInstalled(a), bi = isInstalled(b)
            if ai != bi { return ai && !bi }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var installedCount: Int {
        library.games.filter(isInstalled).count
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if library.isFetchingLibrary && library.games.isEmpty {
                ProgressView("Fetching your library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.games.isEmpty {
                emptyState(icon: "tray", title: "No games yet",
                           message: "Click Refresh to fetch your Steam library.")
            } else if filteredGames.isEmpty {
                if installedOnly {
                    emptyState(icon: "internaldrive", title: "No games installed yet",
                               message: "Open a game in your Library and click Install — it'll show up here.")
                } else {
                    emptyState(icon: "magnifyingglass", title: "No matches",
                               message: "No games match “\(searchText)”.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(filteredGames) { game in
                            GameCardView(
                                game: game,
                                isInstalled: isInstalled(game),
                                action: { onSelectGame(game) }
                            )
                        }
                    }
                    .padding(22)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(installedOnly ? "Search installed" : "Search library", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
            Spacer()
            Text(installedOnly
                 ? "\(filteredGames.count) installed"
                 : "\(installedCount) installed · \(library.games.count) games")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await library.fetchLibrary(auth: auth) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .disabled(library.isFetchingLibrary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 42)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
// MARK: - Game capsule card (clickable, opens detail)

struct GameCardView: View {
    let game: SteamLibraryGame
    let isInstalled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: game.headerImage) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(Color.secondary.opacity(0.15))
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle().fill(Color.secondary.opacity(0.15))
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        @unknown default:
                            Rectangle().fill(Color.secondary.opacity(0.15))
                        }
                    }
                    .frame(height: 108)
                    .clipped()

                    if isInstalled {
                        Text("INSTALLED")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name)
                        .font(.callout.bold())
                        .lineLimit(1)
                    Text("appID \(game.appID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isHovering ? 2 : 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
