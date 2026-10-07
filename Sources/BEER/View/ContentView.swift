import SwiftUI

// MARK: - Root

// ContentView is just a router. Onboarding flows take over the entire window
// until the user has DepotDownloader installed and is signed in. After that, the
// main app shell (sidebar + content) takes over. Bottle-specific controls live
// in each installed game's Advanced section; the sidebar manages runtimes.
struct ContentView: View {
    @EnvironmentObject private var depot: DepotDownloaderInstaller
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @EnvironmentObject private var presence: SteamPresenceStore

    var body: some View {
        Group {
            if !depot.isInstalled {
                DepotDownloaderSetupView()
            } else if !library.account.isLoggedIn {
                // SteamSignInView surfaces library.lastError inline; don't alert.
                SteamSignInView()
            } else {
                MainShellView()
            }
        }
        // Modal alerts only for errors that aren't already shown inline
        // (i.e. after the user is signed in).
        .alert("BEER", isPresented: Binding(
            get: {
                library.account.isLoggedIn &&
                (store.lastError != nil || runtimeInstaller.lastError != nil ||
                 library.lastError != nil || depot.lastError != nil)
            },
            set: {
                if !$0 {
                    store.lastError = nil
                    runtimeInstaller.lastError = nil
                    library.lastError = nil
                    depot.lastError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                store.lastError = nil
                runtimeInstaller.lastError = nil
                library.lastError = nil
                depot.lastError = nil
            }
        } message: {
            Text(store.lastError ?? runtimeInstaller.lastError ?? library.lastError ?? depot.lastError ?? "")
        }
        .task {
            await runtimeInstaller.refresh()
            if library.account.isLoggedIn {
                // Bring the Steam session up before the library fetch: the
                // status the user picked should apply from the moment the app
                // is usable, not once a network round-trip finishes.
                await presence.start(auth: cloudAuth)
                await library.fetchLibrary(auth: cloudAuth)
            }
        }
        // Sign-in and sign-out both happen well after launch, so the session
        // has to follow the account rather than only the app's lifetime.
        .onChange(of: library.account.isLoggedIn) { _, isLoggedIn in
            Task {
                if isLoggedIn {
                    await presence.start(auth: cloudAuth)
                } else {
                    await presence.stop()
                }
            }
        }
    }
}

// MARK: - Main shell (after onboarding)

enum AppSidebarItem: String, Hashable, CaseIterable, Identifiable {
    case library
    case installed
    case downloads
    case runtimes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .library: "Library"
        case .installed: "Installed"
        case .downloads: "Downloads"
        case .runtimes: "Runtime Manager"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "rectangle.stack.fill"
        case .installed: "internaldrive.fill"
        case .downloads: "arrow.down.circle"
        case .runtimes: "shippingbox.fill"
        }
    }
}

struct MainShellView: View {
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @EnvironmentObject private var presence: SteamPresenceStore
    @StateObject private var depotController = DepotDownloaderController()
    @StateObject private var downloads = DownloadsStore()
    @StateObject private var goldberg = GoldbergInstaller()
    @StateObject private var cloudSync = CloudSyncEngine()
    @StateObject private var graphicsTranslator = GraphicsTranslatorInstaller()
    @StateObject private var dlcStore = DLCStore()
    @State private var sidebar: AppSidebarItem = .library
    @State private var selectedGameAppID: Int?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $sidebar) {
                Section {
                    ForEach(AppSidebarItem.allCases) { item in
                        Label(item.label, systemImage: item.systemImage).tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("BEER")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    SteamAccountBar()
                }
            }
            .frame(minWidth: 200)
        } detail: {
            switch sidebar {
            case .library:
                LibraryPane(selectedGameAppID: $selectedGameAppID)
                    .environmentObject(depotController)
                    .environmentObject(downloads)
                    .environmentObject(goldberg)
                    .environmentObject(cloudSync)
                    .environmentObject(graphicsTranslator)
                    .environmentObject(dlcStore)
            case .installed:
                LibraryPane(selectedGameAppID: $selectedGameAppID, installedOnly: true)
                    .environmentObject(depotController)
                    .environmentObject(downloads)
                    .environmentObject(goldberg)
                    .environmentObject(cloudSync)
                    .environmentObject(graphicsTranslator)
                    .environmentObject(dlcStore)
            case .downloads:
                DownloadsPane()
                    .environmentObject(depotController)
                    .environmentObject(downloads)
            case .runtimes:
                RuntimeManagerView()
                    .environmentObject(graphicsTranslator)
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Switching tabs returns to that tab's grid rather than carrying a
        // selected game across (e.g. Library → Installed shouldn't show a detail).
        .onChange(of: sidebar) { _, _ in
            selectedGameAppID = nil
            columnVisibility = .all
        }
        .task {
            depotController.load()
            goldberg.refresh()
            graphicsTranslator.refresh()
        }
    }
}

// MARK: - Library pane (grid + detail)

struct LibraryPane: View {
    @Binding var selectedGameAppID: Int?
    var installedOnly: Bool = false
    @EnvironmentObject private var library: SteamLibraryStore

    var body: some View {
        if let appID = selectedGameAppID,
           let game = library.games.first(where: { $0.appID == appID }) {
            GameDetailView(
                game: game,
                onBack: { selectedGameAppID = nil }
            )
        } else {
            SteamLibraryGridView(
                onSelectGame: { selectedGameAppID = $0.appID },
                installedOnly: installedOnly
            )
        }
    }
}

// MARK: - Account bar

/// The signed-in account, bottom-left: avatar, Steam nickname, and the same
/// four-state status menu the Steam client puts on the user's own name.
///
/// Identity here is Steam's, not ours: the nickname and avatar come from the
/// live session's persona (`SteamPresenceStore`), so what shows up matches what
/// friends see. The stored account name is only a fallback for before the
/// session has reported in.
private struct SteamAccountBar: View {
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @EnvironmentObject private var presence: SteamPresenceStore

    var body: some View {
        HStack(spacing: 10) {
            avatar
                .frame(width: 32, height: 32)
                .clipShape(Circle())

            Menu {
                Picker("Status", selection: Binding(
                    get: { presence.desiredState },
                    set: { presence.setState($0) }
                )) {
                    ForEach(SteamPersonaState.allCases) { state in
                        Text(state.caption.map { "\(state.label) — \($0)" } ?? state.label)
                            .tag(state)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.callout.bold())
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // A Steam session that has failed is otherwise invisible: the app
            // keeps working, the status line just quietly stops being true.
            if let problem = presence.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(problem)
            }

            Menu {
                Button("Sign Out", role: .destructive) {
                    library.signOut()
                    cloudAuth.signOut()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    fallbackAvatar
                }
            }
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.tint)
    }

    private var avatarURL: URL? {
        presence.persona?.avatarURL
            ?? library.account.avatarURL.flatMap { URL(string: $0) }
    }

    /// Steam's nickname once the session reports it; the account name until then.
    private var displayName: String {
        if let name = presence.persona?.name, !name.isEmpty { return name }
        return library.account.username
    }

    private var statusLine: String {
        if let appID = presence.persona?.currentAppID {
            let game = library.games.first { $0.appID == appID }
            return game.map { "In-Game · \($0.name)" } ?? "In-Game"
        }
        if let state = presence.persona?.state { return state.label }
        return presence.isConnected ? "Connecting…" : SteamPersonaState.offline.label
    }

    private var statusTint: Color {
        if presence.persona?.currentAppID != nil { return .green }
        guard let state = presence.persona?.state else { return .secondary }
        return state.tint
    }
}
