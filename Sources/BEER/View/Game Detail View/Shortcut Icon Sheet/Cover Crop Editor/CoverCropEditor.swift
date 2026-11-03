import SwiftUI

/// The cover with a square on it: drag the square to choose what the icon
/// shows. Everything outside the square is dimmed.
struct CoverCropEditor: View {
    let cover: CGImage
    @Binding var crop: CoverCrop
    @State private var dragStart: CoverCrop?

    var body: some View {
        let imageSize = CGSize(width: cover.width, height: cover.height)
        let width = ShortcutIconSheetLayout.coverWidth
        let height = width * imageSize.height / imageSize.width
        let ratio = width / imageSize.width
        let square = crop.rect(in: imageSize)
        let shown = CGRect(x: square.minX * ratio, y: square.minY * ratio,
                           width: square.width * ratio, height: square.height * ratio)

        Image(decorative: cover, scale: 1)
            .resizable()
            .frame(width: width, height: height)
            .overlay {
                Path { path in
                    path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
                    path.addRect(shown)
                }
                .fill(Color.black.opacity(ShortcutIconSheetLayout.dimOpacity), style: FillStyle(eoFill: true))
            }
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: ShortcutIconSheetLayout.cropBorderWidth)
                    .frame(width: shown.width, height: shown.height)
                    .offset(x: shown.minX, y: shown.minY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        let start = dragStart ?? crop
                        dragStart = start
                        var moved = start
                        moved.centerX += drag.translation.width / width
                        moved.centerY += drag.translation.height / height
                        crop = moved
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}
