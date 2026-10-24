import Foundation

extension FileManager {
    /// Removes `url`, treating "already gone" as success. Any other failure,
    /// such as a permissions error, still throws. Use this instead of
    /// `try? removeItem` so a delete that matters can't fail silently.
    func removeItemIfPresent(at url: URL) throws {
        do {
            try removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}
