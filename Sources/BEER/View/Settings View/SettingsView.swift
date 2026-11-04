import SwiftUI

/// The Settings window (⌘,): how BEER looks, and the Wine runtimes it runs on.
struct SettingsView: View {
    @AppStorage(AppearancePreferences.settingsTabKey) private var tab: SettingsTab = .appearance

    var body: some View {
        TabView(selection: $tab) {
            AppearanceSettingsView()
                .frame(width: SettingsLayout.appearanceSize.width, height: SettingsLayout.appearanceSize.height)
                .tabItem { Label(SettingsTab.appearance.label, systemImage: SettingsTab.appearance.systemImage) }
                .tag(SettingsTab.appearance)
            RuntimeManagerView()
                .frame(width: SettingsLayout.runtimesSize.width, height: SettingsLayout.runtimesSize.height)
                .tabItem { Label(SettingsTab.runtimes.label, systemImage: SettingsTab.runtimes.systemImage) }
                .tag(SettingsTab.runtimes)
        }
    }
}
