import SwiftUI

// The DLC manager sheet. Lists the DLC this account owns for a game and
// installs them into the existing install directory — the base game is never
// re-downloaded.
//
// Progress comes from DownloadsStore, the same place base-game installs report
// to, so a DLC download stays visible in the Downloads pane even if this sheet
// is dismissed mid-install.
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
    @EnvironmentObject private var downloads: DownloadsStore
    @EnvironmentObject private var cloudAuth: SteamAuthStore

    @State private var isInstallingAll = false

    private var liveBottle: Bottle { bottles.live(bottle) }
    private var owned: [CloudSyncClient.DLCInfo] { dlcStore.state(for: game.appID).owned }

    /// `isInstalling` drops to false between items of a batch; gate on the batch
    /// flag too so buttons don't flicker back to enabled mid-run.
    private var isBusy: Bool { depotCtl.isBusy || isInstallingAll }

    var body: some View {
        // Hoisted: effectiveInstalledDLC sorts on every access, and these were
        // being recomputed once per row per body pass.
        let installedIDs = Set(liveBottle.effectiveInstalledDLC.map(\.appID))
        let pending = owned.filter { !installedIDs.contains($0.appID) }

        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content(installedIDs: installedIDs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer(pending: pending)
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
    private func content(installedIDs: Set<Int>) -> some View {
        switch dlcStore.state(for: game.appID) {
        case .idle, .loading:
            centered {
                ProgressView()
                Text("Checking which DLC your Steam account owns…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let reason):
            placeholder(icon: "exclamationmark.triangle.fill", tint: .orange, text: reason)
        case .loaded(let entries) where entries.filter(\.owned).isEmpty:
            placeholder(
                icon: "shippingbox",
                tint: .secondary,
                text: entries.isEmpty
                    ? "Steam doesn't list any DLC for this game."
                    : "Steam lists \(entries.count) DLC for this game, but none are on your account."
            )
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !emulatorApplied {
                        emulatorWarning
                    }
                    ForEach(owned) { dlc in
                        row(dlc, installed: installedIDs.contains(dlc.appID))
                        Divider()
                    }
                }
            }
        }
    }

    private func placeholder(icon: String, tint: Color, text: String) -> some View {
        centered {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Check again") { reload() }
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
    private func row(_ dlc: CloudSyncClient.DLCInfo, installed: Bool) -> some View {
        let active = downloads.entry(for: dlc.appID).flatMap { $0.isActive ? $0 : nil }

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

                if let active {
                    ProgressView(value: active.fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 260)
                    Text(active.phaseText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if active != nil {
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

    private func footer(pending: [CloudSyncClient.DLCInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = dlcStore.message {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(message.isError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if !pending.isEmpty {
                    Button(isInstallingAll ? "Installing…" : "Install all (\(pending.count))") {
                        installAll(pending)
                    }
                    .disabled(isBusy)
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
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

    private func reload() {
        guard let auth = cloudAuth.account else { return }
        Task { await dlcStore.load(appID: game.appID, auth: auth, force: true) }
    }

    private func install(_ dlc: CloudSyncClient.DLCInfo) {
        guard let auth = cloudAuth.account else { return }
        Task { await installOne(dlc, auth: auth) }
    }

    private func installAll(_ queue: [CloudSyncClient.DLCInfo]) {
        guard let auth = cloudAuth.account else { return }
        isInstallingAll = true
        Task {
            defer { isInstallingAll = false }
            // One auth session for the batch: each DLC still gets its own
            // DepotDownloader run, but they no longer re-mint the credential
            // cache — and re-authenticating per item is what Steam throttles.
            try? await depotCtl.withAuthSession(auth: auth) {
                // Serially: parallel runs would fight over the install dir.
                for dlc in queue {
                    await installOne(dlc, auth: auth)
                    if dlcStore.message?.isError == true { break }
                }
            }
        }
    }

    private func installOne(_ dlc: CloudSyncClient.DLCInfo, auth: SteamCloudAccount) async {
        await dlcStore.install(
            dlc, bottle: liveBottle, installDir: installDir, auth: auth,
            controller: depotCtl, downloads: downloads, bottles: bottles
        )
    }

    private func disable(_ dlc: CloudSyncClient.DLCInfo) {
        guard let record = liveBottle.effectiveInstalledDLC.first(where: { $0.appID == dlc.appID }) else { return }
        Task {
            await dlcStore.disable(record, bottle: liveBottle, installDir: installDir, bottles: bottles)
        }
    }
}
