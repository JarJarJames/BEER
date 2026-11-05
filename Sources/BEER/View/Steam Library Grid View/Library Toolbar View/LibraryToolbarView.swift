import SwiftUI

struct LibraryToolbarView: View {
    @Binding var searchText: String
    @Binding var filter: LibraryFilter
    let filters: [LibraryFilter]
    let summary: String
    var onAddNonSteamGame: () -> Void = {}
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var auth: SteamAuthStore
    @AppStorage(AppearancePreferences.cardStyleKey) private var cardStyle = AppearanceDefaults.cardStyle
    @AppStorage(AppearancePreferences.sortOrderKey) private var sortOrder = AppearanceDefaults.sortOrder

    var body: some View {
        HStack(spacing: 10) {
            Picker(LibraryFilter.pickerLabel, selection: $filter) {
                ForEach(filters) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                .padding(.leading, 6)
            TextField(filter.searchPrompt, text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
            Spacer()
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(AppearanceStrings.cardStyle, selection: $cardStyle) {
                ForEach(LibraryCardStyle.allCases) { style in
                    Image(systemName: style.systemImage)
                        .help(style.label)
                        .tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Menu {
                Picker(AppearanceStrings.sortOrder, selection: $sortOrder) {
                    ForEach(LibrarySortOrder.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(AppearanceStrings.sortOrder, systemImage: "arrow.up.arrow.down")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(AppearanceStrings.sortOrder)
            // Opens the Settings window, where the rest of the look is set.
            SettingsLink {
                Label(AppearanceStrings.customize, systemImage: "paintbrush")
            }
            .labelStyle(.iconOnly)
            .help(AppearanceStrings.customize)
            Button(action: onAddNonSteamGame) {
                Label("Add Non-Steam Game", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .help("Add Non-Steam Game")
            Button {
                Task { await library.fetchLibrary(auth: auth) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .disabled(library.isFetchingLibrary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
}
