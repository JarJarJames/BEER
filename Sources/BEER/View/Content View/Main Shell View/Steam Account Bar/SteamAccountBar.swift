import SwiftUI

/// The signed-in account, bottom-left: avatar, Steam nickname, and the same
/// four-state status menu the Steam client puts on the user's own name.
///
/// Identity here is Steam's, not ours: the nickname and avatar come from the
/// live session's persona (`SteamPresenceStore`), so what shows up matches what
/// friends see. The stored account name is only a fallback for before the
/// session has reported in.
struct SteamAccountBar: View {
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @EnvironmentObject private var presence: SteamPresenceStore

    var body: some View {
        HStack(spacing: 10) {
            avatar
                .frame(width: 32, height: 32)
                .clipShape(Circle())

            Menu {
                Picker("Status", selection: Binding(
                    get: { presence.desiredState },
                    set: { presence.setState($0) }
                )) {
                    ForEach(SteamPersonaState.allCases) { state in
                        Text(state.caption.map { "\(state.label) — \($0)" } ?? state.label)
                            .tag(state)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.callout.bold())
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // A Steam session that has failed is otherwise invisible: the app
            // keeps working, the status line just quietly stops being true.
            if let problem = presence.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(problem)
            }

            Menu {
                Button("Sign Out", role: .destructive) {
                    library.signOut()
                    cloudAuth.signOut()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    fallbackAvatar
                }
            }
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.tint)
    }

    private var avatarURL: URL? {
        presence.persona?.avatarURL
            ?? library.account.avatarURL.flatMap { URL(string: $0) }
    }

    /// Steam's nickname once the session reports it; the account name until then.
    private var displayName: String {
        if let name = presence.persona?.name, !name.isEmpty { return name }
        return library.account.username
    }

    private var statusLine: String {
        if let appID = presence.persona?.currentAppID {
            let game = library.games.first { $0.appID == appID }
            return game.map { "In-Game · \($0.name)" } ?? "In-Game"
        }
        if let state = presence.persona?.state { return state.label }
        return presence.isConnected ? "Connecting…" : SteamPersonaState.offline.label
    }

    private var statusTint: Color {
        if presence.persona?.currentAppID != nil { return .green }
        guard let state = presence.persona?.state else { return .secondary }
        return state.tint
    }
}
