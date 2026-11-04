import Foundation

extension GameDetailViewModel {
    /// Copies the picked image into BEER and uses it for `slot`.
    func chooseArtwork(_ source: URL, for slot: GameArtSlot) {
        artworkError = nil
        do {
            let copy = try CustomArtFiles.copy(source, appID: appID, slot: slot)
            library.setCustomArt(copy.path, slot: slot, appID: appID)
        } catch {
            artworkError = GameOrganizeStrings.copyFailed(error.localizedDescription)
        }
    }

    /// Back to Steam's art for `slot`; the copy is deleted.
    func resetArtwork(_ slot: GameArtSlot) {
        artworkError = nil
        library.setCustomArt(nil, slot: slot, appID: appID)
    }
}
