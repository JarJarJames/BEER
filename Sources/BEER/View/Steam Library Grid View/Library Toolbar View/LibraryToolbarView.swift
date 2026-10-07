import SwiftUI

struct LibraryToolbarView: View {
    @Binding var searchText: String
    let installedOnly: Bool
    let summary: String
    var onAddNonSteamGame: () -> Void = {}
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var auth: SteamAuthStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(installedOnly ? "Search installed" : "Search library", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
            Spacer()
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
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
