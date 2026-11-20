import SwiftUI

struct RuntimeCatalogPlaceholder: View {
    @Environment(RuntimeInstaller.self) private var runtimeInstaller

    var body: some View {
        if runtimeInstaller.isRefreshing {
            RuntimeLoadingRow(text: "Loading available releases…")
        } else {
            RuntimeEmptyRow(text: "No releases loaded. Use Refresh to try again.")
        }
    }
}
