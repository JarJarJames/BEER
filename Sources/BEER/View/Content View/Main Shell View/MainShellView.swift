import SwiftUI

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
    @StateObject private var windowsDependencies = WindowsDependencyInstaller()
    @StateObject private var dlcStore = DLCStore()
    @State private var sidebar: AppSidebarItem = .library
    @State private var selectedGameAppID: Int?
    /// A game a shortcut asked for, held while the sidebar switches to Library.
    @State private var linkedAppID: Int?
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
                    .environmentObject(windowsDependencies)
                    .environmentObject(dlcStore)
            case .installed:
                LibraryPane(selectedGameAppID: $selectedGameAppID, installedOnly: true)
                    .environmentObject(depotController)
                    .environmentObject(downloads)
                    .environmentObject(goldberg)
                    .environmentObject(cloudSync)
                    .environmentObject(graphicsTranslator)
                    .environmentObject(windowsDependencies)
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
            selectedGameAppID = linkedAppID
            linkedAppID = nil
            columnVisibility = .all
        }
        // On the next turn of the run loop: when a shortcut launches BEER the
        // link is waiting before the first frame, and opening the game page
        // mid-layout sends the window's toolbar into a layout loop (crash).
        .onReceive(GameLinkRouter.shared.$requestedAppID.receive(on: DispatchQueue.main)) { appID in
            guard let appID else { return }
            GameLinkRouter.shared.requestedAppID = nil
            if sidebar == .library || sidebar == .installed {
                selectedGameAppID = appID
            } else {
                linkedAppID = appID
                sidebar = .library
            }
        }
        .task {
            depotController.load()
            goldberg.refresh()
            graphicsTranslator.refresh()
        }
    }
}
