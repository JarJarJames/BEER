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
