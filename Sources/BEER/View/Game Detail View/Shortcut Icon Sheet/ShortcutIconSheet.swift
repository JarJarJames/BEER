import SwiftUI

/// Picks what a game's shortcuts show: a square of its cover, or Steam's own
/// icon when Steam has one at 256×256 or larger.
struct ShortcutIconSheet: View {
    @StateObject private var model: ShortcutIconViewModel
    let onSave: (ShortcutIconChoice) -> Void
    let onCancel: () -> Void

    init(game: SteamLibraryGame, account: SteamCloudAccount?, rememberClientIcon: @escaping (URL) -> Void,
         onSave: @escaping (ShortcutIconChoice) -> Void, onCancel: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ShortcutIconViewModel(
            game: game, account: account, rememberClientIcon: rememberClientIcon
        ))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var usesSteamIcon: Binding<Bool> {
        Binding(
            get: { model.choice == .steamIcon },
            set: { model.choice = $0 ? .steamIcon : .cover(model.crop) }
        )
    }

    /// 0 shows the largest square; 1 zooms in as far as allowed.
    private var zoom: Binding<Double> {
        Binding(
            get: { (1 - model.crop.scale) / (1 - CoverCrop.minimumScale) },
            set: { model.crop.scale = 1 - $0 * (1 - CoverCrop.minimumScale) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(GameShortcutStrings.sheetTitle)
                .font(.largeTitle.bold())
            Text(model.game.name)
                .font(.title3)
                .foregroundStyle(.secondary)

            Picker("", selection: usesSteamIcon) {
                Text(GameShortcutStrings.coverOption).tag(false)
                Text(GameShortcutStrings.steamIconOption).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.steamIcon == .checking || model.steamIcon == .unavailable)

            switch model.steamIcon {
            case .checking:
                Text(GameShortcutStrings.checkingSteamIcon).font(.callout).foregroundStyle(.secondary)
            case .unavailable where !model.game.effectiveIsNonSteam:
                Text(GameShortcutStrings.noSteamIcon).font(.callout).foregroundStyle(.secondary)
            default:
                EmptyView()
            }

            HStack(alignment: .top, spacing: 24) {
                if model.choice != .steamIcon {
                    VStack(alignment: .leading, spacing: 10) {
                        if let cover = model.cover {
                            CoverCropEditor(cover: cover, crop: Binding(get: { model.crop }, set: { model.crop = $0 }))
                            Text(GameShortcutStrings.cropHint).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text(GameShortcutStrings.zoom)
                                Slider(value: zoom, in: 0...1)
                            }
                            .frame(width: ShortcutIconSheetLayout.coverWidth)
                        } else if let error = model.error {
                            Text(error).foregroundStyle(.red)
                        } else {
                            ProgressView()
                        }
                    }
                }
                VStack(spacing: 8) {
                    Text(GameShortcutStrings.preview).font(.headline)
                    if let preview = model.previewImage {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: ShortcutIconSheetLayout.previewSide, height: ShortcutIconSheetLayout.previewSide)
                            .clipShape(RoundedRectangle(cornerRadius: ShortcutIconSheetLayout.previewCornerRadius))
                    } else {
                        RoundedRectangle(cornerRadius: ShortcutIconSheetLayout.previewCornerRadius)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: ShortcutIconSheetLayout.previewSide, height: ShortcutIconSheetLayout.previewSide)
                    }
                }
            }

            HStack(spacing: 12) {
                Button(GameShortcutStrings.reset) { model.choice = .default }
                    .disabled(model.choice == .default)
                Spacer()
                Button(action: { onSave(model.choice) }) {
                    Text(GameShortcutStrings.save).frame(width: ShortcutIconSheetLayout.buttonWidth)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.previewImage == nil)
                Button(action: onCancel) {
                    Text(GameShortcutStrings.cancel).frame(width: ShortcutIconSheetLayout.buttonWidth)
                }
                .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: ShortcutIconSheetLayout.sheetWidth)
        .task { await model.load() }
    }
}
