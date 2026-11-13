import Foundation

extension CloudSyncClient {
    /// BEER's one logged-on Steam session (see `SteamSessionHost`), which
    /// every command that talks to Steam goes through.
    func session(account: String, refreshToken: String) throws -> SteamSessionHost {
        SteamSessionHost.shared(binary: try binaryOrThrow(), account: account,
                                refreshToken: refreshToken, isTest: binary != nil)
    }

    /// End the session: on sign-out.
    func endSession() async {
        guard let binary = try? binaryOrThrow() else { return }
        await SteamSessionHost.end(binary: binary)
    }

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

    /// Run a command on the session, returning the last JSON object it
    /// answered with.
    func runOnce(args: [String], account: String, refreshToken: String) async throws -> [String: Any] {
        let last = ResultBox()
        try await session(account: account, refreshToken: refreshToken).request(args) { last.accept($0) }
        return try last.result(notes: NoteBox(), ending: "the Steam session ended")
    }

    /// Run a command in a helper process of its own, for the one that never
    /// talks to Steam (`prepare-depot-auth`). The token goes in a temp file so
    /// it never appears in argv / `ps` output.
    func runLocal(args: [String], account: String, refreshToken: String) async throws -> [String: Any] {
        let binary = try binaryOrThrow()
        let tokenFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gn-cloud-\(UUID().uuidString).tok")
        try refreshToken.write(to: tokenFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tokenFile) }

        let fullArgs = args + ["--account", account, "--token-file", tokenFile.path]
        let last = ResultBox()
        let notes = NoteBox()
        let exitCode = try await runStreaming(binary: binary, args: fullArgs, onNote: { notes.add($0) }) { last.accept($0) }
        return try last.result(notes: notes, ending: "process exited \(exitCode)")
    }
}

extension ResultBox {
    /// Keep a helper reply: its error, or the object itself.
    func accept(_ obj: [String: Any]) {
        if let err = obj["error"] as? String {
            setError(err,
                     authFailed: (obj["auth_failed"] as? Bool) ?? false,
                     rateLimited: (obj["rate_limited"] as? Bool) ?? false)
        } else {
            setDict(obj)
        }
    }

    /// The reply, or the error it stands for.
    func result(notes: NoteBox, ending: String) throws -> [String: Any] {
        if rateLimited { throw CloudSyncClientError.rateLimited }
        if authFailed { throw CloudSyncClientError.authExpired }
        if let error { throw CloudSyncClientError.helper(error) }
        guard let obj = dict else {
            // The helper never printed a recognizable JSON line at all — it was
            // killed or crashed outside its own exception handling, so there's
            // no {"error": …} to relay. Fall back to whatever it did print
            // (its stderr notes), rather than the useless "no JSON result", so
            // the real cause isn't lost.
            let detail = notes.all.suffix(15).joined(separator: " | ")
            throw CloudSyncClientError.badOutput(
                detail.isEmpty ? "\(ending) with no output" : "\(detail) (\(ending))"
            )
        }
        return obj
    }
}

extension CloudSyncClient {
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
