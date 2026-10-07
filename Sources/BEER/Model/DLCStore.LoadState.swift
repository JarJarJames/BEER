import Foundation

extension DLCStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded([CloudSyncClient.DLCInfo])
        case failed(String)

        var entries: [CloudSyncClient.DLCInfo] {
            if case .loaded(let found) = self { return found }
            return []
        }

        var owned: [CloudSyncClient.DLCInfo] { entries.filter(\.owned) }
    }
}
