import SwiftUI

/// The Steam-style strip across the bottom of the header: Play and its
/// menu, then the stats. See-through, edge to edge, no border.
/// When the window is too narrow for one line, the stats wrap under Play.
struct GameStatBar: View {
    @ObservedObject var model: GameDetailViewModel
    let stats: [GameStat]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GameBannerLayout.statSpacing) {
                GameActionRow(model: model)
                statColumns
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 14) {
                GameActionRow(model: model)
                statColumns
            }
        }
        .padding(.horizontal, GameBannerLayout.pageInset)
        .padding(.vertical, GameBannerLayout.statBarVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(GameBannerLayout.statBarOpacity))
    }

    private var statColumns: some View {
        HStack(spacing: GameBannerLayout.statSpacing) {
            ForEach(stats) { GameStatColumn(stat: $0) }
        }
    }
}
