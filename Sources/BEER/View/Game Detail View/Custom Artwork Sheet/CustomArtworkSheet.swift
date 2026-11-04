import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Pick a cover, banner and logo for a game in place of Steam's.
struct CustomArtworkSheet: View {
    let game: SteamLibraryGame
    let error: String?
    let onChoose: (URL, GameArtSlot) -> Void
    let onReset: (GameArtSlot) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(GameOrganizeStrings.artworkTitle).font(.title2.bold())
            Text(GameOrganizeStrings.artworkMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(GameArtSlot.allCases) { slot in
                row(slot)
                if slot != GameArtSlot.allCases.last { Divider() }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(GameOrganizeStrings.done, action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: CustomArtworkLayout.sheetWidth)
    }

    private func row(_ slot: GameArtSlot) -> some View {
        HStack(spacing: CustomArtworkLayout.rowSpacing) {
            preview(slot)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.label).font(.headline)
                Text(slot.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                Button(GameOrganizeStrings.chooseImage) { pick(slot) }
                if game.customArt?.path(for: slot) != nil {
                    Button(game.effectiveIsNonSteam ? GameOrganizeStrings.removeImage : GameOrganizeStrings.useSteams) {
                        onReset(slot)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    /// What the slot shows now: the player's pick, or Steam's.
    private func preview(_ slot: GameArtSlot) -> some View {
        let url: URL? = switch slot {
        case .cover: game.portraitCover ?? game.headerImage
        case .banner: game.libraryHeroImage
        case .logo: game.libraryLogoImage
        }
        return Color.black.opacity(0.35)
            .frame(width: CustomArtworkLayout.previewSize.width, height: CustomArtworkLayout.previewSize.height)
            .overlay {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
                .padding(slot == .logo ? 6 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: CustomArtworkLayout.previewCornerRadius))
    }

    private func pick(_ slot: GameArtSlot) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = slot.hint
        if panel.runModal() == .OK, let url = panel.url {
            onChoose(url, slot)
        }
    }
}
