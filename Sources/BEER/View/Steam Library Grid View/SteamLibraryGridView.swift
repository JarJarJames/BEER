import SwiftUI

struct SteamLibraryGridView: View {
    var onSelectGame: (SteamLibraryGame) -> Void
    /// All games, or only installed ones; switched in the library's bar.
    @Binding var filter: LibraryFilter
    private var installedOnly: Bool { filter == .installed }

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
    @AppStorage(AppearancePreferences.cardStyleKey) private var cardStyle: LibraryCardStyle = .wide
    @AppStorage(AppearancePreferences.cardWidthKey) private var cardWidth = LibraryGridLayout.defaultCardWidth
    @AppStorage(AppearancePreferences.captionKey) private var caption: LibraryCaption = .appID
    @AppStorage(AppearancePreferences.showsNamesKey) private var showsNames = true
    @AppStorage(AppearancePreferences.playtimeFormatKey) private var playtimeFormat: PlaytimeFormat = .decimalHours
    @AppStorage(AppearancePreferences.lastPlayedFormatKey) private var lastPlayedFormat: LastPlayedFormat = .date
    @AppStorage(AppearancePreferences.sortOrderKey) private var sortOrder: LibrarySortOrder = .installedFirst
    /// The scroll area's width, so no card is made wider than the view.
    @State private var gridWidth: CGFloat = 0

    private var columns: [GridItem] {
        if cardStyle == .list {
            return [GridItem(.flexible())]
        }
        let width = LibraryGridLayout.cardWidth(style: cardStyle, chosen: cardWidth,
                                                available: gridWidth - LibraryGridLayout.gridPadding * 2)
        return [GridItem(.adaptive(minimum: width.lowerBound, maximum: width.upperBound),
                         spacing: LibraryGridLayout.gridSpacing, alignment: .top)]
    }

    var body: some View {
        let installedIDs = Set(bottles.bottles.map(\.id))
        let driveMissingIDs = Set(bottles.bottles.filter {
            $0.gameDrive != nil && bottles.installLocation(of: $0).missingDriveName != nil
        }.map(\.id))
        let games = model.filteredGames(from: library.games, installedBottleIDs: installedIDs, installedOnly: installedOnly,
                                         sortOrder: sortOrder)

        VStack(spacing: 0) {
            LibraryToolbarView(
                searchText: $model.searchText,
                filter: $filter,
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
                    LazyVGrid(columns: columns,
                              spacing: cardStyle == .list ? LibraryGridLayout.listSpacing : LibraryGridLayout.gridSpacing) {
                        ForEach(games) { game in
                            GameCardView(
                                game: game,
                                isInstalled: model.isInstalled(game, installedBottleIDs: installedIDs),
                                isDriveMissing: game.installedBottleID.map(driveMissingIDs.contains) ?? false,
                                style: cardStyle,
                                cardWidth: cardWidth,
                                caption: caption.text(for: game, playtime: playtimeFormat, lastPlayed: lastPlayedFormat),
                                showsName: showsNames,
                                action: { onSelectGame(game) }
                            )
                        }
                    }
                    .padding(LibraryGridLayout.gridPadding)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
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
