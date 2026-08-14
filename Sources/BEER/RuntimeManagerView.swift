import SwiftUI

struct RuntimeManagerView: View {
    @EnvironmentObject private var detector: ToolchainDetector
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller
    @EnvironmentObject private var translators: GraphicsTranslatorInstaller

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
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

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Runtime Manager")
                    .font(.largeTitle.bold())
                Text("Install and manage Wine and Game Porting Toolkit runtimes. Assign a runtime to a game from that game's settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Task {
                    await detector.refresh()
                    await runtimeInstaller.refresh()
                    await detector.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(detector.isRefreshing || runtimeInstaller.isRefreshing || runtimeInstaller.isInstalling)
        }
    }

    private var installedRuntimes: some View {
        runtimeSection(title: "Installed runtimes", description: "Wine and GPTK builds currently available to installed games.") {
            if detector.isRefreshing && detector.candidates.isEmpty {
                loadingRow("Scanning for installed runtimes…")
            } else if detector.candidates.isEmpty {
                emptyRow("No Wine or GPTK runtimes were detected.")
            } else {
                ForEach(detector.candidates) { runtime in
                    HStack(spacing: 12) {
                        Image(systemName: runtime.kind == .gamePortingToolkit ? "hammer.fill" : "wineglass.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(runtime.displayName)
                                .font(.callout.weight(.medium))
                            Text("\(runtime.kind.label) · \(runtime.locationPath)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
    }

    private var gptkCatalog: some View {
        runtimeSection(title: "Game Porting Toolkit", description: "Apple-focused Wine builds with D3DMetal for the best DirectX performance on Apple silicon.") {
            if runtimeInstaller.availableReleases.isEmpty {
                catalogPlaceholder
            } else {
                ForEach(runtimeInstaller.availableReleases, id: \.tag) { release in
                    releaseRow(release)
                    Divider()
                }
            }
        }
    }

    private var wineCatalog: some View {
        runtimeSection(title: "Mainline Wine", description: "Newer Wine builds for games GPTK cannot run. Use WineD3D, DXVK, or DXMT instead of D3DMetal.") {
            if runtimeInstaller.availableWineBuilds.isEmpty {
                catalogPlaceholder
            } else {
                ForEach(runtimeInstaller.availableWineBuilds, id: \.tag) { release in
                    releaseRow(release)
                    Divider()
                }
            }
        }
    }

    private var graphicsTranslators: some View {
        runtimeSection(title: "Graphics translators", description: "D3D→Metal/Vulkan layers for mainline Wine. GPTK includes its own D3DMetal translator.") {
            ForEach(GraphicsTranslator.allCases) { translator in
                translatorRow(translator)
                Divider()
            }
        }
    }

    private var catalogPlaceholder: some View {
        Group {
            if runtimeInstaller.isRefreshing {
                loadingRow("Loading available releases…")
            } else {
                emptyRow("No releases loaded. Use Refresh to try again.")
            }
        }
    }

    private func runtimeSection<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
    }

    @ViewBuilder
    private func releaseRow(_ release: RuntimeRelease) -> some View {
        let installed = runtimeInstaller.isInstalled(release)
        let busy = runtimeInstaller.installingTag == release.tag
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(release.tag).font(.callout.weight(.medium))
                Text("\(release.assetName) · \(release.displaySize)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Button {
                    Task { await runtimeInstaller.install(release); await detector.refresh() }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .disabled(runtimeInstaller.isInstalling)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func translatorRow(_ t: GraphicsTranslator) -> some View {
        let downloaded = translators.installed.contains(t)
        let busy = translators.busy == t
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(t.displayName).font(.callout.weight(.medium))
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else if downloaded {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Button {
                    Task { try? await translators.ensureDownloaded(t) }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .disabled(translators.busy != nil)
            }
        }
        .padding(.vertical, 8)
    }
}
