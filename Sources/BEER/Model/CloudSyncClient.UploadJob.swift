import Foundation

extension CloudSyncClient {
    struct UploadJob { let filename: String; let local: URL; let mtime: Date }
}
