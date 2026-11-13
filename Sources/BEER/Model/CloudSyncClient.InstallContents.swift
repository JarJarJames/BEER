import Foundation

extension CloudSyncClient {
    /// What a Windows install is made of, as the helper's `installsize` reports it.
    struct InstallContents: Equatable {
        /// Nil when Steam lists no size.
        let bytes: Int64?
        /// Every depot the download fetches.
        let depotIDs: [Int]
        /// The owned DLC among them.
        let dlc: [InstallableDLC]
        /// Each depot's own size, for the depots Steam lists one for.
        var depotBytes: [Int: Int64] = [:]
    }
}
