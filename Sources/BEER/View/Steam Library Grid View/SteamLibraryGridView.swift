import SwiftUI

struct SteamLibraryGridView: View {
    var onSelectGame: (SteamLibraryGame) -> Void
    /// When true, show only installed games (the "Installed" sidebar tab).
    var installedOnly: Bool = false

    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var bottles: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector
    /// Observed so a tile's "drive not connected" badge follows the drive.
    @EnvironmentObject private var drives: InstallVolumeMonitor
    @EnvironmentObject private var foundGames: FoundGamesStore
    @StateObject private var model = SteamLibraryGridViewModel()
    @State private var isAddingNonSteamGame = false
    /// The drive whose found games are being reviewed.
    @State private var reviewingDriveID: String?

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 18, alignment: .top)
    ]

    var body: some View {
        let installedIDs = Set(bottles.bottles.map(\.id))
        let driveMissingIDs = Set(bottles.bottles.filter {
            $0.gameDrive != nil && bottles.installLocation(of: $0).missingDriveName != nil
        }.map(\.id))
        let games = model.filteredGames(from: library.games, installedBottleIDs: installedIDs, installedOnly: installedOnly)

        VStack(spacing: 0) {
            LibraryToolbarView(
                searchText: $model.searchText,
                installedOnly: installedOnly,
                summary: installedOnly
                    ? "\(games.count) installed"
                    : "\(model.installedCount(in: library.games, installedBottleIDs: installedIDs)) installed · \(library.games.count) games",
                onAddNonSteamGame: { isAddingNonSteamGame = true }
            )
            Divider()
            ForEach(foundGames.byDrive, id: \.drive.id) { group in
                FoundGamesBanner(
                    driveName: group.drive.name, count: group.games.count,
                    onReview: { reviewingDriveID = group.drive.id },
                    onDismiss: { foundGames.dismiss(driveID: group.drive.id) }
                )
                .padding([.horizontal, .top], FoundGamesLayout.bannerInset)
            }
            if library.isFetchingLibrary && library.games.isEmpty {
                ProgressView("Fetching your library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.games.isEmpty {
                LibraryEmptyStateView(icon: "tray", title: "No games yet",
                                      message: "Click Refresh to fetch your Steam library.")
            } else if games.isEmpty {
                if installedOnly {
                    LibraryEmptyStateView(icon: "internaldrive", title: "No games installed yet",
                                          message: "Open a game in your Library and click Install — it'll show up here.")
                } else {
                    LibraryEmptyStateView(icon: "magnifyingglass", title: "No matches",
                                          message: "No games match “\(model.searchText)”.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(games) { game in
                            GameCardView(
                                game: game,
                                isInstalled: model.isInstalled(game, installedBottleIDs: installedIDs),
                                isDriveMissing: game.installedBottleID.map(driveMissingIDs.contains) ?? false,
                                action: { onSelectGame(game) }
                            )
                        }
                    }
                    .padding(22)
                }
            }
        }
        .sheet(isPresented: Binding(get: { reviewingDriveID != nil }, set: { if !$0 { reviewingDriveID = nil } })) {
            if let group = foundGames.byDrive.first(where: { $0.drive.id == reviewingDriveID }) {
                FoundGamesSheet(
                    driveName: group.drive.name, games: group.games, isAdding: foundGames.isAdding,
                    onAdd: { picked in
                        guard let runtime = detector.preferredGameRuntime else { return }
                        Task {
                            await foundGames.add(picked, runtime: runtime, bottles: bottles, library: library)
                            reviewingDriveID = nil
                            await foundGames.scan(drives: drives.drives, bottles: bottles.bottles, library: library.games)
                        }
                    },
                    onCancel: { reviewingDriveID = nil }
                )
            }
        }
        .alert(FoundGamesStrings.sheetTitle, isPresented: Binding(
            get: { !foundGames.errors.isEmpty },
            set: { if !$0 { foundGames.errors = [] } }
        )) {
            Button(InstallDriveStrings.cancelButton, role: .cancel) { foundGames.errors = [] }
        } message: {
            Text(foundGames.errors.joined(separator: "\n"))
        }
        .sheet(isPresented: $isAddingNonSteamGame) {
            AddNonSteamGameSheet(bottles: bottles, library: library, detector: detector, drives: drives)
        }
    }
}
