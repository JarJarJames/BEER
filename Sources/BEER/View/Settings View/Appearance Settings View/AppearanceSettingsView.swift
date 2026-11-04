import SwiftUI

/// The Settings window's Appearance tab: how the library and game pages look.
struct AppearanceSettingsView: View {
    @AppStorage(AppearancePreferences.cardStyleKey) private var cardStyle = AppearanceDefaults.cardStyle
    @AppStorage(AppearancePreferences.cardWidthKey) private var cardWidth = AppearanceDefaults.cardWidth
    @AppStorage(AppearancePreferences.cardLabelKey) private var cardLabel = AppearanceDefaults.cardLabel
    @AppStorage(AppearancePreferences.sortOrderKey) private var sortOrder = AppearanceDefaults.sortOrder
    @AppStorage(AppearancePreferences.layoutKey) private var layout = AppearanceDefaults.layout
    @AppStorage(AppearancePreferences.bannerHeightKey) private var bannerHeight = AppearanceDefaults.bannerHeight
    @AppStorage(AppearancePreferences.titleScaleKey) private var titleScale = AppearanceDefaults.titleScale
    @AppStorage(AppearancePreferences.showsBackdropKey) private var showsBackdrop = AppearanceDefaults.showsBackdrop
    @AppStorage(AppearancePreferences.shownStatsKey) private var shownStats = AppearanceDefaults.shownStats
    @AppStorage(AppearancePreferences.playtimeFormatKey) private var playtimeFormat = AppearanceDefaults.playtimeFormat
    @AppStorage(AppearancePreferences.lastPlayedFormatKey) private var lastPlayedFormat = AppearanceDefaults.lastPlayedFormat

    var body: some View {
        Form {
            Section {
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
                Picker(AppearanceStrings.cardLabel, selection: $cardLabel) {
                    ForEach(LibraryCardLabel.allCases) { Text($0.label).tag($0) }
                }
                Picker(AppearanceStrings.sortOrder, selection: $sortOrder) {
                    ForEach(LibrarySortOrder.allCases) { Text($0.label).tag($0) }
                }
                resetButton {
                    cardStyle = AppearanceDefaults.cardStyle
                    cardWidth = AppearanceDefaults.cardWidth
                    cardLabel = AppearanceDefaults.cardLabel
                    sortOrder = AppearanceDefaults.sortOrder
                }
            } header: {
                Text(AppearanceStrings.librarySection)
            } footer: {
                Text(AppearanceStrings.libraryFooter)
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
                Slider(value: $titleScale, in: GameBannerLayout.titleScaleRange) {
                    Text(AppearanceStrings.titleSize)
                } minimumValueLabel: {
                    Image(systemName: "textformat.size.smaller")
                } maximumValueLabel: {
                    Image(systemName: "textformat.size.larger")
                }
                Toggle(AppearanceStrings.backdrop, isOn: $showsBackdrop)
                resetButton {
                    layout = AppearanceDefaults.layout
                    bannerHeight = AppearanceDefaults.bannerHeight
                    titleScale = AppearanceDefaults.titleScale
                    showsBackdrop = AppearanceDefaults.showsBackdrop
                }
            }

            Section(AppearanceStrings.statsSection) {
                ForEach(GamePageStat.allCases) { stat in
                    Toggle(stat.label, isOn: shows(stat))
                }
                resetButton { shownStats = AppearanceDefaults.shownStats }
            }

            Section {
                Picker(AppearanceStrings.playtimeFormat, selection: $playtimeFormat) {
                    ForEach(PlaytimeFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker(AppearanceStrings.lastPlayedFormat, selection: $lastPlayedFormat) {
                    ForEach(LastPlayedFormat.allCases) { Text($0.label).tag($0) }
                }
                resetButton {
                    playtimeFormat = AppearanceDefaults.playtimeFormat
                    lastPlayedFormat = AppearanceDefaults.lastPlayedFormat
                }
            } header: {
                Text(AppearanceStrings.playStatsSection)
            } footer: {
                Text(AppearanceStrings.playStatsFooter)
            }
        }
        .formStyle(.grouped)
    }

    /// Puts one section back to how BEER looked before these settings.
    private func resetButton(_ reset: @escaping () -> Void) -> some View {
        HStack {
            Button(AppearanceStrings.resetToDefaults, action: reset)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
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
