import Foundation

extension CloudSyncClient {
    struct DLCInfo: Identifiable, Equatable {
        var id: Int { appID }
        let appID: Int
        let name: String
        let owned: Bool
        /// False for licence-only DLC (season passes, artbooks) that carry no
        /// downloadable depot — there is nothing to install for those, only an
        /// entitlement to declare to the Steam emulator.
        let hasDepots: Bool
    }
}
