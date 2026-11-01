import Foundation

extension CloudSyncClient {
    /// One Windows launch option from the app's Steam `config/launch` section,
    /// as the helper's `launchinfo` command reports it. Paths are relative to
    /// the install root and use backslashes, exactly as Steam stores them.
    struct LaunchEntry: Equatable {
        let executable: String
        let arguments: String

        init(executable: String, arguments: String = "") {
            self.executable = executable
            self.arguments = arguments
        }

        init?(json: [String: Any]) {
            guard let executable = json["executable"] as? String, !executable.isEmpty else { return nil }
            self.init(executable: executable, arguments: json["arguments"] as? String ?? "")
        }
    }
}
