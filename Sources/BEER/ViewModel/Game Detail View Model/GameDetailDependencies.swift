import Combine

/// The stores `GameDetailViewModel` reads and drives. Bundled so the view can
/// hand them over in one value — they come from the SwiftUI environment, which
/// a `@StateObject` initializer can't read directly.
struct GameDetailDependencies {
    let library: SteamLibraryStore
    let bottles: BottleStore
    let detector: ToolchainDetector
    let depotCtl: DepotDownloaderController
    let downloads: DownloadsStore
    let goldberg: GoldbergInstaller
    let cloudAuth: SteamAuthStore
    let cloudSync: CloudSyncEngine
    let presence: SteamPresenceStore
    let graphicsTranslator: GraphicsTranslatorInstaller
    let dlcStore: DLCStore

    var changePublishers: [ObservableObjectPublisher] {
        [
            library.objectWillChange, bottles.objectWillChange, detector.objectWillChange,
            depotCtl.objectWillChange, downloads.objectWillChange, goldberg.objectWillChange,
            cloudAuth.objectWillChange, cloudSync.objectWillChange, presence.objectWillChange,
            graphicsTranslator.objectWillChange, dlcStore.objectWillChange
        ]
    }
}
