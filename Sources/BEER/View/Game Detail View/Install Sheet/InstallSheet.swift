import SwiftUI

// Shown before a game downloads, like Steam's install dialog: the game's size
// and the disk's free space, with Install turned off when it won't fit.

struct InstallSheet: View {
    let game: SteamLibraryGame
    /// Nil while the size and free space are looked up.
    let report: InstallSpaceReport?
    let onInstall: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let shortfall: DiskSpaceShortfall? = if case .short(let s) = report?.verdict { s } else { nil }

        VStack(alignment: .leading, spacing: 16) {
            Text(InstallSheetStrings.title)
                .font(.largeTitle.bold())

            Divider()
            HStack(spacing: 14) {
                AsyncImage(url: game.headerImage) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: InstallSheetLayout.artworkWidth, height: InstallSheetLayout.artworkHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(game.name)
                    .font(.title3)
                    .lineLimit(2)
                    // A sheet sizes to its content; without this the name
                    // truncates to one line instead of wrapping to two.
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let report {
                    Text(report.installBytes.map(InstallSheetStrings.size) ?? InstallSheetStrings.unknownSize)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Divider()

            Text(InstallSheetStrings.installTo)
                .font(.headline)
            HStack {
                Image(systemName: "internaldrive")
                Text(report?.volume?.name ?? (report == nil ? InstallSheetStrings.checking : InstallSheetStrings.unknownVolume))
                    .font(.title3)
                Spacer()
                if let volume = report?.volume {
                    Text(InstallSheetStrings.free(volume.availableBytes))
                        .font(.headline)
                }
            }
            .padding(14)
            .foregroundStyle(.white)
            .background(shortfall == nil ? Color.accentColor : Color.red, in: RoundedRectangle(cornerRadius: 6))

            if let shortfall {
                Text(DiskSpaceStrings.shortfall(shortfall))
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .unchecked(let note) = report?.verdict {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Spacer()
                Button(action: onInstall) {
                    Text(InstallSheetStrings.installButton)
                        .frame(width: InstallSheetLayout.buttonWidth)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(report == nil || shortfall != nil)

                Button(action: onCancel) {
                    Text(InstallSheetStrings.cancelButton)
                        .frame(width: InstallSheetLayout.buttonWidth)
                }
                .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: InstallSheetLayout.sheetWidth)
    }
}
