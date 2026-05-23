import AppKit
import SwiftUI

// Building blocks for the Steam Library flow. ContentView composes these
// directly into the main app shell (no sheet) — the user never sees a
// modal, the library IS the app once they're set up.
//
//   • SteamCMDSetupView — full-window onboarding step 1
//   • SteamSignInView   — full-window onboarding step 2
//   • SteamLibraryGridView — primary post-onboarding view (grid of capsules)
//   • GameCardView      — single clickable capsule

// MARK: - Onboarding step 1: install SteamCMD

struct DepotDownloaderSetupView: View {
    @EnvironmentObject private var depot: DepotDownloaderInstaller

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Welcome to GameNative")
                .font(.largeTitle.bold())
            Text("First, we'll install DepotDownloader — an open-source, native macOS Steam downloader. No Wine, no Steam client UI, and you sign in by scanning a QR code with the Steam Mobile App instead of typing a password.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 600)
                .fixedSize(horizontal: false, vertical: true)

            if depot.isInstalling {
                ProgressView().controlSize(.large)
            }

            Text(depot.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                Task { await depot.install() }
            } label: {
                Label(depot.isInstalled ? "Reinstall DepotDownloader" : "Install DepotDownloader", systemImage: "arrow.down.circle.fill")
                    .font(.title3)
                    .frame(minWidth: 280, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(depot.isInstalling)

            if let error = depot.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Onboarding step 2: sign in

struct SteamSignInView: View {
    @EnvironmentObject private var library: SteamLibraryStore
    @State private var profile: String = ""
    @State private var apiKey: String = ""
    @FocusState private var profileFocused: Bool

    private var canSubmit: Bool {
        !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Sign in to Steam")
                .font(.largeTitle.bold())
            Text("Paste your Steam profile URL (or your vanity / SteamID64) and a free Steam Web API key. We use these to pull your owned-games list. We never see your Steam password — that only gets used later by SteamCMD inside a Terminal window when you install a game.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Steam profile")
                        .font(.callout.bold())
                    TextField("vanity name, profile URL, or 17-digit SteamID64", text: $profile)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .focused($profileFocused)
                        .onSubmit(submit)
                    Text("Examples: `username` · `https://steamcommunity.com/id/username` · `76561198000000000`")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Steam Web API key")
                        .font(.callout.bold())
                    SecureField("32-character API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .onSubmit(submit)
                    HStack(spacing: 4) {
                        Text("Don't have one?")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Link("Get one free in 30 seconds →", destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
                            .font(.caption2)
                    }
                }

                if let error = library.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: 520)

            Button {
                submit()
            } label: {
                HStack {
                    if library.isFetchingLibrary {
                        ProgressView().controlSize(.small)
                        Text("Signing in…")
                    } else {
                        Label("Sign In", systemImage: "arrow.right.circle.fill")
                    }
                }
                .font(.title3)
                .frame(minWidth: 220, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit || library.isFetchingLibrary)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            library.lastError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                profileFocused = true
            }
        }
    }

    private func submit() {
        guard canSubmit, !library.isFetchingLibrary else { return }
        library.lastError = nil
        Task { await library.signIn(profile: profile, webAPIKey: apiKey) }
    }
}

// MARK: - Library grid

struct SteamLibraryGridView: View {
    var onSelectGame: (SteamLibraryGame) -> Void

    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var bottles: BottleStore
    @State private var searchText: String = ""

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 18, alignment: .top)
    ]

    private var filteredGames: [SteamLibraryGame] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return library.games }
        return library.games.filter { $0.name.lowercased().contains(q) || String($0.appID).contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if library.isFetchingLibrary && library.games.isEmpty {
                ProgressView("Fetching your library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.games.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(filteredGames) { game in
                            GameCardView(
                                game: game,
                                isInstalled: bottles.bottles.contains { $0.id == game.installedBottleID },
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
            TextField("Search library", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
            Spacer()
            Text("\(library.games.count) games")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await library.fetchLibrary() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .disabled(library.isFetchingLibrary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 42)).foregroundStyle(.secondary)
            Text("No games yet").font(.headline)
            Text("Click Refresh to fetch your Steam library.")
                .font(.callout)
                .foregroundStyle(.secondary)
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
