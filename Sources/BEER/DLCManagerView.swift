import SwiftUI

// The DLC manager sheet. Lists the DLC this account owns for a game and
// installs them into the existing install directory — the base game is never
// re-downloaded.
struct DLCManagerView: View {
    let game: SteamLibraryGame
    let bottle: Bottle
    let installDir: URL
    /// Whether the Steam emulator has been applied. Without it the
    /// `[app::dlcs]` block has no steam_settings folder to live in, so DLC
    /// would download but stay invisible to the game.
    let emulatorApplied: Bool
    let onDone: () -> Void

    @EnvironmentObject private var dlcStore: DLCStore
    @EnvironmentObject private var bottles: BottleStore
    @EnvironmentObject private var depotCtl: DepotDownloaderController
    @EnvironmentObject private var cloudAuth: SteamAuthStore

    @State private var isInstallingAll = false

    private var liveBottle: Bottle {
        bottles.bottles.first { $0.id == bottle.id } ?? bottle
    }

    private var installedIDs: Set<Int> {
        Set(liveBottle.effectiveInstalledDLC.map(\.appID))
    }

    private var owned: [CloudSyncClient.DLCInfo] { dlcStore.owned }

    /// `isInstalling` drops to false between items of a batch; gate on the batch
    /// flag too so buttons don't flicker back to enabled mid-run.
    private var isBusy: Bool { dlcStore.isInstalling || isInstallingAll }

    private var pending: [CloudSyncClient.DLCInfo] {
        owned.filter { !installedIDs.contains($0.appID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(width: 560, height: 520)
        .task {
            guard let auth = cloudAuth.account else { return }
            await dlcStore.load(appID: game.appID, auth: auth)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Downloadable Content").font(.title3.bold())
            Text(game.name)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch dlcStore.state {
        case .idle, .loading:
            centered {
                ProgressView()
                Text("Checking which DLC your Steam account owns…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let reason):
            centered {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Button("Try again") { reload(force: true) }
            }
        case .loaded where owned.isEmpty:
            centered {
                Image(systemName: "shippingbox")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(dlcStore.entries.isEmpty
                     ? "Steam doesn't list any DLC for this game."
                     : "Steam lists \(dlcStore.entries.count) DLC for this game, but none are on your account.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Button("Check again") { reload(force: true) }
            }
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !emulatorApplied {
                        emulatorWarning
                    }
                    ForEach(owned) { dlc in
                        row(dlc)
                        Divider()
                    }
                }
            }
        }
    }

    private var emulatorWarning: some View {
        Label(
            "The Steam emulator isn't applied to this game yet. DLC will download, but the game can't see it until you apply the emulator from Game Settings.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }

    @ViewBuilder
    private func row(_ dlc: CloudSyncClient.DLCInfo) -> some View {
        let installed = installedIDs.contains(dlc.appID)
        let progress = dlcStore.progress[dlc.appID]

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dlc.name).font(.callout.weight(.medium))
                HStack(spacing: 8) {
                    Text("appID \(dlc.appID)")
                    if !dlc.hasDepots {
                        Text("No files to download")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let progress {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 260)
                    Text(progress.phase)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if progress != nil {
                ProgressView().controlSize(.small)
            } else if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Menu {
                    Button("Reinstall") { install(dlc) }
                    Button("Disable", role: .destructive) { disable(dlc) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(isBusy)
            } else {
                Button(dlc.hasDepots ? "Install" : "Enable") { install(dlc) }
                    .controlSize(.small)
                    .disabled(isBusy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = dlcStore.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(dlcStore.messageIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if !pending.isEmpty {
                    Button(isInstallingAll ? "Installing…" : "Install all (\(pending.count))") {
                        installAll()
                    }
                    .disabled(isBusy)
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
            }
        }
        .padding(20)
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 12, content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }

    // MARK: - Actions

    private func reload(force: Bool) {
        guard let auth = cloudAuth.account else { return }
        Task { await dlcStore.load(appID: game.appID, auth: auth, force: force) }
    }

    private func install(_ dlc: CloudSyncClient.DLCInfo) {
        guard let auth = cloudAuth.account else { return }
        Task {
            await dlcStore.install(
                dlc, bottle: liveBottle, installDir: installDir,
                auth: auth, controller: depotCtl, bottles: bottles
            )
        }
    }

    private func installAll() {
        guard let auth = cloudAuth.account else { return }
        let queue = pending
        isInstallingAll = true
        Task {
            defer { isInstallingAll = false }
            // Serially: each DLC is its own DepotDownloader run and its own
            // Steam logon, and parallel runs would fight over the install dir.
            for dlc in queue {
                await dlcStore.install(
                    dlc, bottle: liveBottle, installDir: installDir,
                    auth: auth, controller: depotCtl, bottles: bottles
                )
                if dlcStore.messageIsError { break }
            }
        }
    }

    private func disable(_ dlc: CloudSyncClient.DLCInfo) {
        guard let record = liveBottle.effectiveInstalledDLC.first(where: { $0.appID == dlc.appID }) else { return }
        Task {
            await dlcStore.disable(record, bottle: liveBottle, installDir: installDir, bottles: bottles)
        }
    }
}
