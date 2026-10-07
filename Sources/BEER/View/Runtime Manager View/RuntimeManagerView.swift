import SwiftUI

struct RuntimeManagerView: View {
    @EnvironmentObject private var detector: ToolchainDetector
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RuntimeManagerHeader()
                installedRuntimes
                gptkCatalog
                wineCatalog
                graphicsTranslators

                Text(runtimeInstaller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await detector.refresh()
            if runtimeInstaller.availableReleases.isEmpty {
                await runtimeInstaller.refresh()
                await detector.refresh()
            }
        }
    }

    private var installedRuntimes: some View {
        RuntimeSection(title: "Installed runtimes", description: "Wine and GPTK builds currently available to installed games.") {
            if detector.isRefreshing && detector.candidates.isEmpty {
                RuntimeLoadingRow(text: "Scanning for installed runtimes…")
            } else if detector.candidates.isEmpty {
                RuntimeEmptyRow(text: "No Wine or GPTK runtimes were detected.")
            } else {
                ForEach(detector.candidates) { runtime in
                    InstalledRuntimeRow(runtime: runtime)
                    Divider()
                }
            }
        }
    }

    private var gptkCatalog: some View {
        RuntimeSection(title: "Game Porting Toolkit", description: "Apple-focused Wine builds with D3DMetal for the best DirectX performance on Apple silicon.") {
            if runtimeInstaller.availableReleases.isEmpty {
                RuntimeCatalogPlaceholder()
            } else {
                ForEach(runtimeInstaller.availableReleases, id: \.tag) { release in
                    RuntimeReleaseRow(release: release)
                    Divider()
                }
            }
        }
    }

    private var wineCatalog: some View {
        RuntimeSection(title: "Mainline Wine", description: "Newer Wine builds for games GPTK cannot run. Use WineD3D, DXVK, or DXMT instead of D3DMetal.") {
            if runtimeInstaller.availableWineBuilds.isEmpty {
                RuntimeCatalogPlaceholder()
            } else {
                ForEach(runtimeInstaller.availableWineBuilds, id: \.tag) { release in
                    RuntimeReleaseRow(release: release)
                    Divider()
                }
            }
        }
    }

    private var graphicsTranslators: some View {
        RuntimeSection(title: "Graphics translators", description: "D3D→Metal/Vulkan layers for mainline Wine. GPTK includes its own D3DMetal translator.") {
            ForEach(GraphicsTranslator.allCases) { translator in
                GraphicsTranslatorRow(translator: translator)
                Divider()
            }
        }
    }
}
