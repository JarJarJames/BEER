import Foundation

extension CloudSyncClient {
    func enumerate(appID: Int, account: String, refreshToken: String) async throws -> [CloudRemoteFile] {
        let raw = try await runOnceArray(
            "files", args: ["enumerate", "--appid", String(appID)],
            account: account, refreshToken: refreshToken
        )
        return raw.compactMap { f in
            guard let filename = f["filename"] as? String else { return nil }
            let size = (f["size"] as? NSNumber)?.intValue ?? 0
            let ts = (f["timestamp"] as? NSNumber)?.doubleValue ?? 0
            let sha = f["sha"] as? String ?? ""
            return CloudRemoteFile(
                filename: filename,
                size: size,
                timestamp: Date(timeIntervalSince1970: ts),
                sha: sha
            )
        }
    }

    /// Run many downloads + uploads inside a SINGLE logged-on helper session.
    /// One Steam logon for the whole sync — spawning a process per file gets the
    /// account CM-throttled after ~100 logons. `onProgress` fires per completed
    /// op with (completed, total).
    func batch(
        appID: Int,
        downloads: [DownloadJob],
        uploads: [UploadJob],
        account: String,
        refreshToken: String,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> BatchResult {
        guard !downloads.isEmpty || !uploads.isEmpty else { return BatchResult(ops: [], notes: []) }
        let binary = try binaryOrThrow()

        let jobs: [String: Any] = [
            "appid": appID,
            "downloads": downloads.map { ["filename": $0.filename, "out": $0.out.path] },
            "uploads": uploads.map { ["filename": $0.filename, "in": $0.local.path,
                                      "mtime": Int($0.mtime.timeIntervalSince1970)] }
        ]
        let tmp = FileManager.default.temporaryDirectory
        let jobsFile = tmp.appendingPathComponent("gn-cloud-jobs-\(UUID().uuidString).json")
        let tokenFile = tmp.appendingPathComponent("gn-cloud-\(UUID().uuidString).tok")
        try JSONSerialization.data(withJSONObject: jobs).write(to: jobsFile, options: .atomic)
        try refreshToken.write(to: tokenFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: jobsFile)
            try? FileManager.default.removeItem(at: tokenFile)
        }

        let total = downloads.count + uploads.count
        let collector = BatchCollector()
        _ = try await runStreaming(binary: binary, args: [
            "batch", "--appid", String(appID), "--jobs", jobsFile.path,
            "--account", account, "--token-file", tokenFile.path
        ], onNote: { collector.addNote($0) }) { obj in
            if obj["summary"] != nil { return }
            if let opName = obj["op"] as? String, let filename = obj["filename"] as? String {
                let err = obj["error"] as? String
                collector.add(BatchOp(op: opName, filename: filename, error: err))
                onProgress(collector.count, total)
            } else if let err = obj["error"] as? String {
                // Top-level failure (e.g. the single logon failed before any op).
                collector.setFatal(err,
                                   authFailed: (obj["auth_failed"] as? Bool) ?? false,
                                   rateLimited: (obj["rate_limited"] as? Bool) ?? false)
            }
        }

        if collector.rateLimited { throw CloudSyncClientError.rateLimited }
        if collector.authFailed { throw CloudSyncClientError.authExpired }
        if let fatal = collector.fatal, collector.ops.isEmpty { throw CloudSyncClientError.helper(fatal) }
        return BatchResult(ops: collector.ops, notes: collector.notes)
    }
}
