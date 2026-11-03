import SwiftUI

/// Pick where to move an installed game, laid out like the install sheet: the
/// game's size, then each place with its free space.
struct MoveGameSheet: View {
    let bottle: Bottle
    @ObservedObject var model: GameDetailViewModel

    var body: some View {
        let shortfall = model.moveShortfall

        VStack(alignment: .leading, spacing: 16) {
            Text(GameMoveStrings.sheetTitle)
                .font(.largeTitle.bold())

            Divider()
            HStack {
                Text(model.game.name)
                    .font(.title3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let bytes = model.moveSourceBytes {
                    Text(GameMoveStrings.size(bytes))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Divider()

            Text(GameMoveStrings.moveTo)
                .font(.headline)
            InstallTargetList(options: model.moveOptions, selection: $model.moveTarget,
                              selectionDoesNotFit: shortfall != nil)

            if let shortfall {
                Text(DiskSpaceStrings.shortfall(shortfall))
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Spacer()
                Button { model.confirmMove(bottle) } label: {
                    Text(GameMoveStrings.confirmButton)
                        .frame(width: InstallSheetLayout.buttonWidth)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.moveTarget == nil || model.moveSourceBytes == nil || shortfall != nil)

                Button { model.isShowingMoveSheet = false } label: {
                    Text(GameMoveStrings.cancelButton)
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
