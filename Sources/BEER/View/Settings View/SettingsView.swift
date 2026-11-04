import SwiftUI

/// The Settings window (⌘,): how the library and game pages look.
struct SettingsView: View {
    @AppStorage(AppearancePreferences.cardStyleKey) private var cardStyle: LibraryCardStyle = .wide
    @AppStorage(AppearancePreferences.cardWidthKey) private var cardWidth = LibraryGridLayout.defaultCardWidth
    @AppStorage(AppearancePreferences.captionKey) private var caption: LibraryCaption = .appID
    @AppStorage(AppearancePreferences.showsNamesKey) private var showsNames = true
    @AppStorage(AppearancePreferences.sortOrderKey) private var sortOrder: LibrarySortOrder = .installedFirst
    @AppStorage(AppearancePreferences.bannerHeightKey) private var bannerHeight = GameBannerLayout.defaultHeightRatio
    @AppStorage(AppearancePreferences.titleStyleKey) private var titleStyle: GameTitleStyle = .logo
    @AppStorage(AppearancePreferences.showsBackdropKey) private var showsBackdrop = false
    @AppStorage(AppearancePreferences.titleScaleKey) private var titleScale = GameBannerLayout.defaultTitleScale
    @AppStorage(AppearancePreferences.layoutKey) private var layout: GamePageLayout = .overlay
    @AppStorage(AppearancePreferences.shownStatsKey) private var shownStats = GamePageStat.encode(GamePageStat.defaultShown)
    @AppStorage(AppearancePreferences.playtimeFormatKey) private var playtimeFormat: PlaytimeFormat = .decimalHours
    @AppStorage(AppearancePreferences.lastPlayedFormatKey) private var lastPlayedFormat: LastPlayedFormat = .date

    var body: some View {
        Form {
            Section(AppearanceStrings.librarySection) {
                Picker(AppearanceStrings.cardStyle, selection: $cardStyle) {
                    ForEach(LibraryCardStyle.allCases) { Text($0.label).tag($0) }
                }
                Slider(value: $cardWidth, in: LibraryGridLayout.cardWidthRange) {
                    Text(AppearanceStrings.cardSize)
                } minimumValueLabel: {
                    Image(systemName: "square.grid.3x3")
                } maximumValueLabel: {
                    Image(systemName: "square")
                }
                Toggle(isOn: $showsNames) {
                    Text(AppearanceStrings.showsNames)
                    Text(AppearanceStrings.showsNamesCaption)
                }
                Picker(AppearanceStrings.caption, selection: $caption) {
                    ForEach(LibraryCaption.allCases) { Text($0.label).tag($0) }
                }
                // Only the list shows a caption when names are off.
                .disabled(!showsNames && cardStyle != .list)
                Picker(AppearanceStrings.sortOrder, selection: $sortOrder) {
                    ForEach(LibrarySortOrder.allCases) { Text($0.label).tag($0) }
                }
            }
            Section(AppearanceStrings.gamePageSection) {
                Picker(AppearanceStrings.layout, selection: $layout) {
                    ForEach(GamePageLayout.allCases) { Text($0.label).tag($0) }
                }
                Slider(value: $bannerHeight, in: GameBannerLayout.heightRatioRange) {
                    Text(AppearanceStrings.bannerSize)
                } minimumValueLabel: {
                    Image(systemName: "rectangle.compress.vertical")
                } maximumValueLabel: {
                    Image(systemName: "rectangle.expand.vertical")
                }
                Picker(AppearanceStrings.titleStyle, selection: $titleStyle) {
                    ForEach(GameTitleStyle.allCases) { Text($0.label).tag($0) }
                }
                Slider(value: $titleScale, in: GameBannerLayout.titleScaleRange) {
                    Text(AppearanceStrings.titleSize)
                } minimumValueLabel: {
                    Image(systemName: "textformat.size.smaller")
                } maximumValueLabel: {
                    Image(systemName: "textformat.size.larger")
                }
                Toggle(AppearanceStrings.backdrop, isOn: $showsBackdrop)
            }
            Section(AppearanceStrings.statsSection) {
                ForEach(GamePageStat.allCases) { stat in
                    Toggle(stat.label, isOn: shows(stat))
                }
            }
            Section {
                Picker(AppearanceStrings.playtimeFormat, selection: $playtimeFormat) {
                    ForEach(PlaytimeFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker(AppearanceStrings.lastPlayedFormat, selection: $lastPlayedFormat) {
                    ForEach(LastPlayedFormat.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text(AppearanceStrings.playStatsSection)
            } footer: {
                Text(AppearanceStrings.playStatsFooter)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func shows(_ stat: GamePageStat) -> Binding<Bool> {
        Binding(
            get: { GamePageStat.decode(shownStats).contains(stat) },
            set: { isOn in
                var stats = GamePageStat.decode(shownStats)
                if isOn { stats.insert(stat) } else { stats.remove(stat) }
                shownStats = GamePageStat.encode(stats)
            }
        )
    }
}
