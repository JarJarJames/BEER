import SwiftUI

/// Opens the Settings window on its Runtimes tab, where Wine and GPTK builds
/// are installed.
struct OpenRuntimesButton: View {
    var title = RuntimeStrings.openRuntimes

    @AppStorage(AppearancePreferences.settingsTabKey) private var tab: SettingsTab = .appearance
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(title) {
            tab = .runtimes
            openSettings()
        }
    }
}
