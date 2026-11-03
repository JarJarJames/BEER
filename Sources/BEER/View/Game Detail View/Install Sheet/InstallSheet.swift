import SwiftUI

// Shown before a game downloads, like Steam's install dialog: the game's size
// and where it can go with each place's free space, with Install turned off
// when it won't fit.

struct InstallSheet: View {
    let game: SteamLibraryGame
    /// Nil while Steam is asked.
    let size: InstallSize?
    /// Free space at the chosen place; nil while it's looked up.
    let report: InstallSpaceReport?
    let options: [InstallTargetOption]
    @Binding var selection: InstallTarget?
    /// Why the place can't be changed, or why Install is off.
    let note: String?
    let onInstall: () -> Void
    let onCancel: () -> Void
    @AppStorage(GameShortcutPreferences.desktopKey) private var createDesktopShortcut = false
    @AppStorage(GameShortcutPreferences.applicationKey) private var createApplicationShortcut = false

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
                if let size {
                    Text(size.bytes.map(InstallSheetStrings.size) ?? InstallSheetStrings.unknownSize)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Divider()

            Text(InstallSheetStrings.installTo)
                .font(.headline)
            InstallTargetList(options: options, selection: $selection, selectionDoesNotFit: shortfall != nil)

            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

            VStack(alignment: .leading, spacing: 6) {
                Toggle(GameShortcutStrings.installDesktop, isOn: $createDesktopShortcut)
                Toggle(GameShortcutStrings.installApplication, isOn: $createApplicationShortcut)
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 12) {
                Spacer()
                Button(action: onInstall) {
                    Text(InstallSheetStrings.installButton)
                        .frame(width: InstallSheetLayout.buttonWidth)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(report == nil || selection == nil || shortfall != nil)

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
