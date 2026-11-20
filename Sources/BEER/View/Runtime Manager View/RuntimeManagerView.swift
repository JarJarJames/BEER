import SwiftUI

struct RuntimeManagerView: View {
    @Environment(ToolchainDetector.self) private var detector
    @Environment(RuntimeInstaller.self) private var runtimeInstaller

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RuntimeManagerHeader()
                installedRuntimes
                beerCatalog
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

    /// Computed once per redraw and handed to each row.
    private var recommended: RuntimeRecommendation? {
        detector.recommendedRuntime(beerReleases: runtimeInstaller.beerReleases, gptkReleases: runtimeInstaller.availableReleases)
    }

    private var installedRuntimes: some View {
        RuntimeSection(title: RuntimeManagerStrings.installedTitle, description: RuntimeManagerStrings.installedDescription) {
            if detector.isRefreshing && detector.candidates.isEmpty {
                RuntimeLoadingRow(text: "Scanning for installed runtimes…")
            } else if detector.candidates.isEmpty {
                RuntimeEmptyRow(text: "No Wine or GPTK runtimes were detected.")
            } else {
                let recommended = recommended
                let beerBuilds = detector.installedBEERBuilds
                if !beerBuilds.isEmpty {
                    RuntimeGroupHeader(title: RuntimeManagerStrings.installedBEERGroup)
                    installedRows(beerBuilds, recommended: recommended)
                    RuntimeGroupHeader(title: RuntimeManagerStrings.installedOtherGroup)
                }
                installedRows(detector.otherInstalledRuntimes, recommended: recommended)
            }
        }
    }

    private func installedRows(_ runtimes: [RuntimeCandidate], recommended: RuntimeRecommendation?) -> some View {
        ForEach(runtimes) { runtime in
            InstalledRuntimeRow(runtime: runtime, recommended: recommended == .installed(runtime))
            Divider()
        }
    }

    private var beerCatalog: some View {
        catalog(title: RuntimeManagerStrings.beerTitle, description: RuntimeManagerStrings.beerDescription,
                releases: runtimeInstaller.beerReleases)
    }

    private var gptkCatalog: some View {
        catalog(title: RuntimeManagerStrings.gptkTitle, description: RuntimeManagerStrings.gptkDescription,
                releases: runtimeInstaller.availableReleases)
    }

    private func catalog(title: String, description: String, releases: [RuntimeRelease]) -> some View {
        RuntimeSection(title: title, description: description) {
            if releases.isEmpty {
                RuntimeCatalogPlaceholder()
            } else {
                let recommended = recommended
                ForEach(releases, id: \.tag) { release in
                    RuntimeReleaseRow(release: release, recommended: recommended == .release(release))
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
