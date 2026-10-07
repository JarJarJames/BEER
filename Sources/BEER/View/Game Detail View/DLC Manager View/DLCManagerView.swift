import SwiftUI

// The DLC manager sheet. Lists the DLC this account owns for a game and
// installs them into the existing install directory — the base game is never
// re-downloaded.
//
// Progress comes from DownloadsStore, the same place base-game installs report
// to, so a DLC download stays visible in the Downloads pane even if this sheet
// is dismissed mid-install.
struct DLCManagerView: View {
    /// Whether the Steam emulator has been applied. Without it the
    /// `[app::dlcs]` block has no steam_settings folder to live in, so DLC
    /// would download but stay invisible to the game.
    let emulatorApplied: Bool
    let onDone: () -> Void

    @StateObject private var model: DLCManagerViewModel

    init(
        game: SteamLibraryGame,
        bottle: Bottle,
        installDir: URL,
        emulatorApplied: Bool,
        dependencies: GameDetailDependencies,
        onDone: @escaping () -> Void
    ) {
        self.emulatorApplied = emulatorApplied
        self.onDone = onDone
        _model = StateObject(wrappedValue: DLCManagerViewModel(
            game: game, bottle: bottle, installDir: installDir, dependencies: dependencies
        ))
    }

    var body: some View {
        // Hoisted: these were being recomputed once per row per body pass.
        let installedIDs = model.installedIDs
        let pending = model.owned.filter { !installedIDs.contains($0.appID) }

        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content(installedIDs: installedIDs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            DLCManagerFooter(pending: pending, model: model, onDone: onDone)
        }
        .frame(width: 560, height: 520)
        .task { await model.loadIfNeeded() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Downloadable Content").font(.title3.bold())
            Text(model.game.name)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    @ViewBuilder
    private func content(installedIDs: Set<Int>) -> some View {
        switch model.loadState {
        case .idle, .loading:
            CenteredContentView {
                ProgressView()
                Text("Checking which DLC your Steam account owns…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let reason):
            DLCPlaceholderView(
                icon: "exclamationmark.triangle.fill", tint: .orange, text: reason,
                onRetry: model.reload
            )
        case .loaded(let entries) where entries.filter(\.owned).isEmpty:
            DLCPlaceholderView(
                icon: "shippingbox",
                tint: .secondary,
                text: entries.isEmpty
                    ? "Steam doesn't list any DLC for this game."
                    : "Steam lists \(entries.count) DLC for this game, but none are on your account.",
                onRetry: model.reload
            )
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !emulatorApplied {
                        DLCEmulatorWarning()
                    }
                    ForEach(model.owned) { dlc in
                        DLCManagerRow(dlc: dlc, installed: installedIDs.contains(dlc.appID), model: model)
                        Divider()
                    }
                }
            }
        }
    }
}
