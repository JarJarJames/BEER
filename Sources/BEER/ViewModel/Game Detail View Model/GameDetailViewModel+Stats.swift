import Foundation

extension GameDetailViewModel {
    /// Measures the game's folder for the Size stat. Nil when the game isn't
    /// installed or its drive isn't connected.
    func measureInstalledSize() async {
        guard let bottle = installedBottle, let folder = bottles.installLocation(of: bottle).url else {
            installedBytes = nil
            return
        }
        // Walks the whole game folder.
        installedBytes = await Task.detached { DiskSpaceCheck.allocatedSize(of: folder) }.value
    }
}
