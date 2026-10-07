import Foundation

struct CloudSyncReport {
    var downloaded: Int = 0
    var uploaded: Int = 0
    var skipped: Int = 0
    var failures: [(filename: String, reason: String)] = []
    var backupPath: URL? = nil
}
