import Foundation

extension CloudSyncClient {
    /// Run a one-shot command, returning the last JSON object the helper
    /// printed. Writes the refresh token to a temp file so it never appears in
    /// argv / `ps` output.
    /// Run a command whose payload is a JSON array under `key`, and hand back
    /// its rows. Owns the cast and the "no <key> array" error so each command
    /// keeps only its own row mapping.
    func runOnceArray(
        _ key: String, args: [String], account: String, refreshToken: String
    ) async throws -> [[String: Any]] {
        let obj = try await runOnce(args: args, account: account, refreshToken: refreshToken)
        guard let raw = obj[key] as? [[String: Any]] else {
            throw CloudSyncClientError.badOutput("no \(key) array")
        }
        return raw
    }

    func runOnce(args: [String], account: String, refreshToken: String) async throws -> [String: Any] {
        let binary = try binaryOrThrow()
        let tokenFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gn-cloud-\(UUID().uuidString).tok")
        try refreshToken.write(to: tokenFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tokenFile) }

        let fullArgs = args + ["--account", account, "--token-file", tokenFile.path]
        let last = ResultBox()
        let notes = NoteBox()
        let exitCode = try await runStreaming(binary: binary, args: fullArgs, onNote: { notes.add($0) }) { obj in
            if let err = obj["error"] as? String {
                last.setError(err,
                              authFailed: (obj["auth_failed"] as? Bool) ?? false,
                              rateLimited: (obj["rate_limited"] as? Bool) ?? false)
            } else {
                last.setDict(obj)
            }
        }
        if last.rateLimited { throw CloudSyncClientError.rateLimited }
        if last.authFailed { throw CloudSyncClientError.authExpired }
        if let err = last.error { throw CloudSyncClientError.helper(err) }
        guard let obj = last.dict else {
            // The helper never printed a recognizable JSON line at all — it was
            // killed or crashed outside its own exception handling, so there's
            // no {"error": …} to relay. Fall back to whatever it did print
            // (its stderr notes) plus the exit code, rather than the useless
            // "no JSON result", so the real cause isn't lost.
            let detail = notes.all.suffix(15).joined(separator: " | ")
            throw CloudSyncClientError.badOutput(
                detail.isEmpty ? "process exited \(exitCode) with no output" : "\(detail) (exit \(exitCode))"
            )
        }
        return obj
    }

    /// Stream the helper, decoding each stdout line as JSON and forwarding any
    /// object to `onObject`. Returns the process exit code.
    func runStreaming(
        binary: URL,
        args: [String],
        onNote: (@Sendable (String) -> Void)? = nil,
        onObject: @escaping @Sendable ([String: Any]) -> Void
    ) async throws -> Int32 {
        let leftover = LineBox()
        let result = try await ShellRunner.run(
            executable: binary.path,
            arguments: args,
            environment: ["DOTNET_CLI_TELEMETRY_OPTOUT": "1", "DOTNET_NOLOGO": "1"],
            outputHandler: { chunk in
                for line in leftover.feed(chunk) {
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { onNote?(line); continue }
                    onObject(obj)
                }
            }
        )
        for line in leftover.flush() {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                onObject(obj)
            } else {
                onNote?(line)
            }
        }
        return result.exitCode
    }
}
