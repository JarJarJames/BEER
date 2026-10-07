import SwiftUI

struct RuntimeCatalogPlaceholder: View {
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller

    var body: some View {
        if runtimeInstaller.isRefreshing {
            RuntimeLoadingRow(text: "Loading available releases…")
        } else {
            RuntimeEmptyRow(text: "No releases loaded. Use Refresh to try again.")
        }
    }
}
