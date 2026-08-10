import SwiftUI

struct RuntimeSummaryView: View {
    @EnvironmentObject private var detector: ToolchainDetector

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Runtime")
                .font(.caption)
                .foregroundStyle(.secondary)
            if detector.isRefreshing {
                Label("Scanning...", systemImage: "magnifyingglass")
                    .font(.callout)
            } else if detector.candidates.isEmpty {
                Label("No Wine runtime found", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Label("\(detector.candidates.count) available", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
    }
}

struct RuntimeManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var detector: ToolchainDetector
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller
    @EnvironmentObject private var translators: GraphicsTranslatorInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runtime Manager")
                        .font(.title2.bold())
                    Text("Download Game Porting Toolkit versions. Different games run best on different builds — assign one per game in its Compatibility section.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") { dismiss() }
            }

            HStack {
                Text("Game Porting Toolkit versions").font(.headline)
                if runtimeInstaller.isRefreshing { ProgressView().controlSize(.small) }
                Spacer()
                Button {
                    Task { await runtimeInstaller.refresh(); await detector.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                }
                .disabled(runtimeInstaller.isRefreshing || runtimeInstaller.isInstalling)
            }

            ScrollView {
                VStack(spacing: 0) {
                    if runtimeInstaller.availableReleases.isEmpty {
                        Text(runtimeInstaller.isRefreshing ? "Loading releases…" : "No releases loaded. Click Refresh.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(runtimeInstaller.availableReleases, id: \.tag) { release in
                            releaseRow(release)
                            Divider()
                        }
                    }

                    if !runtimeInstaller.availableWineBuilds.isEmpty {
                        HStack(spacing: 6) {
                            Text("Mainline Wine").font(.headline)
                            Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 14)
                        Text("Newer Wine for games GPTK can't run (e.g. missing-function crashes). No D3DMetal — set the game's Graphics to WineD3D. Slower than GPTK, but it runs. (DXVK needs separate setup; that's coming later.)")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)
                        ForEach(runtimeInstaller.availableWineBuilds, id: \.tag) { release in
                            releaseRow(release)
                            Divider()
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Graphics translators").font(.headline)
                        Spacer()
                    }
                    .padding(.top, 14)
                    Text("D3D→Metal/Vulkan layers for mainline Wine (GPTK has its own D3DMetal). Auto-installed into a game's bottle when you pick that backend; download here to pre-stage.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    ForEach(GraphicsTranslator.allCases) { t in
                        translatorRow(t)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 340)

            Text(runtimeInstaller.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 640)
        .task {
            if runtimeInstaller.availableReleases.isEmpty {
                await runtimeInstaller.refresh()
            }
        }
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


