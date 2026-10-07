import Foundation

extension CloudSyncClient {
    /// Make BEER's existing SteamClient token available to DepotDownloader for
    /// one process invocation. The returned cache URL contains a credential and
    /// must be removed by the caller immediately after DepotDownloader exits.
    func prepareDepotDownloaderAuth(
        executable: URL,
        account: String,
        refreshToken: String
    ) async throws -> URL {
        let obj = try await runOnce(
            args: ["prepare-depot-auth", "--depot-executable", executable.resolvingSymlinksInPath().path],
            account: account,
            refreshToken: refreshToken
        )
        guard obj["prepared"] as? Bool == true,
              let path = obj["config_path"] as? String
        else {
            throw CloudSyncClientError.badOutput("DepotDownloader auth bridge did not return a cache path")
        }
        return URL(fileURLWithPath: path)
    }

    /// Run the QR sign-in. `onChallenge` is called with each challenge URL
    /// (Steam rotates it every ~30s, so the UI should re-render the QR each
    /// time). Returns the account name + a SteamClient-audience refresh token.
    func authenticate(onChallenge: @escaping @Sendable (String) -> Void) async throws -> AuthResult {
        let binary = try binaryOrThrow()
        let captured = ResultBox()

        _ = try await runStreaming(binary: binary, args: ["auth"]) { obj in
            if let url = obj["challenge_url"] as? String {
                onChallenge(url)
            } else if obj["authenticated"] != nil,
                      let account = obj["account"] as? String,
                      let token = obj["refresh_token"] as? String {
                captured.set(AuthResult(account: account, refreshToken: token))
            } else if let err = obj["error"] as? String {
                captured.setError(err)
            }
        }

        if let err = captured.error { throw CloudSyncClientError.helper(err) }
        guard let result = captured.auth else {
            throw CloudSyncClientError.badOutput("auth finished without a token")
        }
        return result
    }
}
