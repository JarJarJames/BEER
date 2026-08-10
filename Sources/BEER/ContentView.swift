import SwiftUI

// MARK: - Root

// ContentView is just a router. Onboarding flows take over the entire window
// until the user has DepotDownloader installed and is signed in. After that, the
// main app shell (sidebar + content) takes over. Bottles are never shown to
// users on the primary path — they live behind the Compatibility sidebar
// item, for power users.
struct ContentView: View {
    @EnvironmentObject private var depot: DepotDownloaderInstaller
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller
    @EnvironmentObject private var cloudAuth: SteamAuthStore

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
                await library.fetchLibrary(auth: cloudAuth)
            }
        }
    }
}

// MARK: - Main shell (after onboarding)

enum AppSidebarItem: String, Hashable, CaseIterable, Identifiable {
    case library
    case installed
    case downloads
    case compatibility

    var id: String { rawValue }

    var label: String {
        switch self {
        case .library: "Library"
        case .installed: "Installed"
        case .downloads: "Downloads"
        case .compatibility: "Compatibility"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "rectangle.stack.fill"
        case .installed: "internaldrive.fill"
        case .downloads: "arrow.down.circle"
        case .compatibility: "wineglass"
        }
    }
}

struct MainShellView: View {
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @StateObject private var depotController = DepotDownloaderController()
    @StateObject private var downloads = DownloadsStore()
    @StateObject private var goldberg = GoldbergInstaller()
    @StateObject private var cloudSync = CloudSyncEngine()
    @StateObject private var graphicsTranslator = GraphicsTranslatorInstaller()
    @State private var sidebar: AppSidebarItem = .library
    @State private var selectedGameAppID: Int?

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebar) {
                Section {
                    ForEach(AppSidebarItem.allCases) { item in
                        Label(item.label, systemImage: item.systemImage).tag(item)
                    }
                }
            }
            .navigationTitle("BEER")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack(spacing: 10) {
                        if let urlString = library.account.avatarURL, let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Image(systemName: "person.crop.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title)
                                .foregroundStyle(.tint)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(library.account.username).font(.callout.bold()).lineLimit(1)
                            Text("\(library.games.count) games").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Refresh Library") { Task { await library.fetchLibrary(auth: cloudAuth) } }
                            Button("Sign Out", role: .destructive) { library.signOut() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
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
            case .installed:
                LibraryPane(selectedGameAppID: $selectedGameAppID, installedOnly: true)
                    .environmentObject(depotController)
                    .environmentObject(downloads)
                    .environmentObject(goldberg)
                    .environmentObject(cloudSync)
                    .environmentObject(graphicsTranslator)
            case .downloads:
                DownloadsPane()
                    .environmentObject(depotController)
                    .environmentObject(downloads)
            case .compatibility:
                CompatibilityPane()
                    .environmentObject(graphicsTranslator)
            }
        }
        // Switching tabs returns to that tab's grid rather than carrying a
        // selected game across (e.g. Library → Installed shouldn't show a detail).
        .onChange(of: sidebar) { _, _ in selectedGameAppID = nil }
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
