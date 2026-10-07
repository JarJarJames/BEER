import Foundation

extension CloudSyncClient {
    /// Start the long-lived presence helper and hand back its process, which
    /// the caller drives with `send` and ends with `end`. See
    /// `SteamPresenceStore` for what this session is for and why there is
    /// exactly one of it.
    func startPresence(
        steamID64: String,
        account: String,
        refreshToken: String,
        onLine: @escaping @Sendable ([String: Any]) -> Void
    ) throws -> SpawnedProcess {
        let binary = try binaryOrThrow()
        let tokenFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gn-presence-\(UUID().uuidString).tok")
        try refreshToken.write(to: tokenFile, atomically: true, encoding: .utf8)

        PlaySessionLog.start()
        let leftover = LineBox()
        // The helper reads its token once at startup, before it logs on, so the
        // first byte it prints proves it is past that point. Nothing else would
        // remove this file for the life of the app.
        let tokenCleanup = OnceBox { try? FileManager.default.removeItem(at: tokenFile) }

        do {
            let process = try ShellRunner.spawn(
                executable: binary.path,
                arguments: [
                    "presence", "--steamid", steamID64,
                    "--account", account, "--token-file", tokenFile.path,
                ],
                environment: ["DOTNET_CLI_TELEMETRY_OPTOUT": "1", "DOTNET_NOLOGO": "1"],
                outputHandler: { chunk in
                    tokenCleanup.run()
                    PlaySessionLog.append(chunk)
                    for line in leftover.feed(chunk) {
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        onLine(obj)
                    }
                }
            )
            PlaySessionRegistry.record(pid: process.processIdentifier)
            return process
        } catch {
            tokenCleanup.run()
            throw error
        }
    }
}
