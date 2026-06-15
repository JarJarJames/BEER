import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// Building blocks for the Steam Library flow. ContentView composes these
// directly into the main app shell (no sheet) — the user never sees a
// modal, the library IS the app once they're set up.
//
//   • DepotDownloaderSetupView — full-window onboarding step 1
//   • SteamSignInView   — full-window onboarding step 2 (QR sign-in)
//   • SteamLibraryGridView — primary post-onboarding view (grid of capsules)
//   • GameCardView      — single clickable capsule

// MARK: - Onboarding step 1: install DepotDownloader

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
    @EnvironmentObject private var auth: SteamAuthStore

    @State private var session: SteamAuthStore.QRSession?
    @State private var error: String?
    @State private var authTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "qrcode")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Sign in to Steam")
                .font(.largeTitle.bold())
            Text("Scan this code with the Steam Mobile App and tap **Approve**. This signs you in to your library and Cloud saves in one step — your password is never typed into this app.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560)
                .fixedSize(horizontal: false, vertical: true)

            qrView
                .frame(width: 260, height: 260)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if library.isFetchingLibrary {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Fetching your library…").font(.callout).foregroundStyle(.secondary)
                }
            } else if let error {
                VStack(spacing: 10) {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                    Button("Try again") { restart() }
                        .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for approval in the Steam Mobile App…")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "iphone")
                Text("Open Steam on your phone → tap the QR-scan icon (top-left) → scan.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startAuthIfNeeded() }
        .onDisappear { authTask?.cancel() }
    }

    @ViewBuilder
    private var qrView: some View {
        if let urlString = session?.challengeURL, let cgImage = Self.generateQR(from: urlString) {
            Image(decorative: cgImage, scale: 1.0)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if error != nil {
            VStack {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text("Couldn't get a QR from Steam.").foregroundStyle(.black)
            }
        } else {
            ProgressView()
        }
    }

    private func startAuthIfNeeded() {
        guard authTask == nil else { return }
        error = nil
        library.lastError = nil
        authTask = Task {
            do {
                try await auth.runQRAuth { qr in self.session = qr }
                await library.signInWithQR(auth: auth)
                // ContentView re-routes to the library grid once
                // library.account.isLoggedIn flips true.
            } catch is CancellationError {
                // view went away
            } catch let err as SteamAuthError {
                self.error = err.errorDescription ?? "Sign-in failed."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func restart() {
        authTask?.cancel()
        authTask = nil
        session = nil
        error = nil
        startAuthIfNeeded()
    }

    private static func generateQR(from string: String) -> CGImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

// MARK: - Library grid

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
