import SwiftUI

struct SteamCloudRow: View {
    let bottle: Bottle
    @ObservedObject var model: GameDetailViewModel
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @EnvironmentObject private var cloudSync: CloudSyncEngine

    var body: some View {
        let connected = cloudAuth.account != nil
        let expired = cloudAuth.sessionExpired

        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(title: "Steam Cloud") {

                if connected && expired {
                    Label("Sign-in expired", systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else if connected {
                    Label(cloudAuth.account?.accountName ?? "Connected", systemImage: "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else {
                    Label("Not connected", systemImage: "icloud.slash")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                if cloudSync.isSyncing {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                if !connected || expired {
                    Button {
                        model.cloudSyncMessage = nil
                        model.isShowingCloudConnect = true
                    } label: {
                        Label(expired ? "Reconnect" : "Connect", systemImage: "icloud")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if expired {
                        Button(role: .destructive) {
                            model.signOutOfSteamCloud()
                        } label: {
                            Label("Sign Out", systemImage: "icloud.slash")
                        }
                        .controlSize(.small)
                    }
                } else {
                    Button {
                        model.syncSaves(for: bottle, pull: true, push: true)
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(cloudSync.isSyncing)

                    Menu {
                        Button {
                            model.syncSaves(for: bottle, pull: true, push: false)
                        } label: {
                            Label("Pull from cloud", systemImage: "icloud.and.arrow.down")
                        }
                        Button {
                            model.syncSaves(for: bottle, pull: false, push: true)
                        } label: {
                            Label("Push to cloud", systemImage: "icloud.and.arrow.up")
                        }
                        Divider()
                        Button(role: .destructive) {
                            model.confirmClearBottle = bottle
                        } label: {
                            Label("Back up & clear local saves…", systemImage: "trash")
                        }
                        Divider()
                        Button(role: .destructive) {
                            model.signOutOfSteamCloud()
                        } label: {
                            Label("Sign Out", systemImage: "icloud.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(cloudSync.isSyncing)
                }
            }

            if cloudSync.isSyncing && !cloudSync.phase.isEmpty {
                Text(cloudSync.phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let message = model.cloudSyncMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(model.cloudSyncIsError ? .red : .green)
                    .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                    .fixedSize(horizontal: false, vertical: true)
            } else if connected && expired {
                Text("Your Steam sign-in expired or was revoked. Click Reconnect to resume syncing — your local saves and backups are untouched.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                    .fixedSize(horizontal: false, vertical: true)
            } else if connected, let last = cloudSync.lastSyncAt {
                Text("Last synced \(last.formatted(.relative(presentation: .named))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsRow<EmptyView>.captionIndent)
            } else if connected {
                Text("Saves sync both ways with Steam Cloud, so you can move between your PC and this Mac. Every sync backs up your local saves first — nothing is overwritten without a recoverable copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
