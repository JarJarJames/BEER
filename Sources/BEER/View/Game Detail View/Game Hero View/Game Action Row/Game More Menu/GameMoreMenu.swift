import SwiftUI

/// The circled ⋯ beside Play or Install: favorite, hide and artwork for every
/// game, plus files, shortcuts and uninstalling once it's installed.
struct GameMoreMenu: View {
    @ObservedObject var model: GameDetailViewModel
    @EnvironmentObject private var bottles: BottleStore
    @State private var isHovering = false

    /// Only a game BEER can launch gets the file and shortcut items.
    private var launchableBottle: Bottle? {
        guard let bottle = model.installedBottle, bottle.gameLaunchExecutable != nil else { return nil }
        return bottle
    }

    var body: some View {
        Menu {
            GameOrganizeMenuItems(game: model.game)
            Button(GameOrganizeStrings.customizeArtwork) {
                model.artworkError = nil
                model.isShowingArtwork = true
            }
            if let bottle = launchableBottle {
                Divider()
                Button(action: { bottles.revealGameFiles(bottle) }) {
                    Label("Reveal Files", systemImage: "folder")
                }
                Divider()
                Button(GameShortcutStrings.createDesktop) { model.createShortcut(.desktop) }
                Button(GameShortcutStrings.createApplication) { model.createShortcut(.application) }
                Button(GameShortcutStrings.editIcon) { model.isShowingShortcutIcon = true }
                Divider()
                if model.game.effectiveIsNonSteam {
                    Button("Remove Game…", role: .destructive, action: model.requestUninstall)
                        .disabled(model.mover.isMoving(bottle.id))
                } else {
                    Button("Reinstall / Validate", action: model.startInstallOrLogin)
                        .disabled(model.mover.isMoving(bottle.id))
                    Button("Uninstall", role: .destructive, action: model.requestUninstall)
                        .disabled(model.mover.isMoving(bottle.id))
                }
            }
        } label: {
            // A round highlight, not the menu's own rectangle: `.button`
            // with a plain style draws the label as is.
            Image(systemName: "ellipsis")
                .font(.system(size: GameBannerLayout.moreMenuDotsSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: GameBannerLayout.moreMenuSize, height: GameBannerLayout.moreMenuSize)
                .background(Circle().fill(.white.opacity(isHovering ? GameBannerLayout.moreMenuHoverOpacity
                                                                    : GameBannerLayout.moreMenuOpacity)))
                .contentShape(Circle())
                .scaleEffect(isHovering ? GameBannerLayout.moreMenuHoverScale : 1)
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        .help(GameOrganizeStrings.more)
        .accessibilityLabel(GameOrganizeStrings.more)
    }
}
