import SwiftUI

/// The signed-in account, in the top bar's corner: avatar, Steam nickname
/// and status, opening the same four-state status choice the Steam client
/// puts on the user's own name, and Sign Out.
///
/// Identity here is Steam's, not ours: the nickname and avatar come from the
/// live session's persona (`SteamPresenceStore`), so what shows up matches what
/// friends see. The stored account name is only a fallback for before the
/// session has reported in.
///
/// A button with a popover rather than a `Menu`: a toolbar menu draws only a
/// plain title and icon, not the avatar and status line.
struct SteamAccountMenu: View {
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @EnvironmentObject private var presence: SteamPresenceStore
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 8) {
                avatar
                    .frame(width: MainShellLayout.avatarSize, height: MainShellLayout.avatarSize)
                    .clipShape(Circle())
                    // A Steam session that has failed is otherwise invisible:
                    // the app keeps working, the status just stops being true.
                    .overlay(alignment: .bottomTrailing) {
                        if presence.lastError != nil {
                            Circle().fill(.orange).frame(width: 8, height: 8)
                        }
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayName)
                        .font(.callout.bold())
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }
                // Not a `Spacer`: in a toolbar item, SwiftUI turns the whole
                // item into an empty flexible space and the account vanished.
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Set outright, never sized to the text: see `accountMenuWidth`.
            .frame(width: MainShellLayout.accountMenuWidth)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { accountPanel }
    }

    private var accountPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Status", selection: Binding(
                get: { presence.desiredState },
                set: { presence.setState($0) }
            )) {
                ForEach(SteamPersonaState.allCases) { state in
                    Text(state.caption.map { "\(state.label) — \($0)" } ?? state.label)
                        .tag(state)
                }
            }
            .pickerStyle(.radioGroup)

            if let problem = presence.lastError {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            Button("Sign Out", role: .destructive) {
                isOpen = false
                library.signOut()
                cloudAuth.signOut()
            }
        }
        .padding(16)
        .frame(width: MainShellLayout.accountPanelWidth)
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
