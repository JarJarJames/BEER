import Foundation

extension CloudSyncClient {
    /// The game's cloud files and the folders it saves into.
    func enumerate(appID: Int, account: String, refreshToken: String) async throws -> CloudListing {
        try CloudListing(json: await runOnce(
            args: ["enumerate", "--appid", String(appID)],
            account: account, refreshToken: refreshToken
        ))
    }

    /// Run many downloads + uploads as one request on the session — never a
    /// logon per file, which gets the account CM-throttled after ~100 logons.
    /// `onProgress` fires per completed op with (completed, total).
    func batch(
        appID: Int,
        downloads: [DownloadJob],
        uploads: [UploadJob],
        account: String,
        refreshToken: String,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> BatchResult {
        guard !downloads.isEmpty || !uploads.isEmpty else { return BatchResult(ops: []) }

        let jobs: [String: Any] = [
            "appid": appID,
            "downloads": downloads.map { ["filename": $0.filename, "out": $0.out.path] },
            "uploads": uploads.map { ["filename": $0.filename, "in": $0.local.path,
                                      "mtime": Int($0.mtime.timeIntervalSince1970)] }
        ]
        let jobsFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gn-cloud-jobs-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: jobs).write(to: jobsFile, options: .atomic)
        defer { try? FileManager.default.removeItem(at: jobsFile) }

        let total = downloads.count + uploads.count
        let collector = BatchCollector()
        try await session(account: account, refreshToken: refreshToken).request(
            ["batch", "--appid", String(appID), "--jobs", jobsFile.path]
        ) { obj in
            if obj["summary"] != nil { return }
            if let opName = obj["op"] as? String, let filename = obj["filename"] as? String {
                let err = obj["error"] as? String
                collector.add(BatchOp(op: opName, filename: filename, error: err))
                onProgress(collector.count, total)
            } else if let err = obj["error"] as? String {
                // The whole batch failed (e.g. the session couldn't log on).
                collector.setFatal(err,
                                   authFailed: (obj["auth_failed"] as? Bool) ?? false,
                                   rateLimited: (obj["rate_limited"] as? Bool) ?? false)
            }
        }

        if collector.rateLimited { throw CloudSyncClientError.rateLimited }
        if collector.authFailed { throw CloudSyncClientError.authExpired }
        if let fatal = collector.fatal, collector.ops.isEmpty { throw CloudSyncClientError.helper(fatal) }
        return BatchResult(ops: collector.ops)
    }
}
