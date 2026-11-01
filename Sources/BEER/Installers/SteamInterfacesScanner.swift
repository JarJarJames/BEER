import Foundation

// Port of gbe_fork's `generate_interfaces` tool. A game's original
// steam_api.dll names the exact interface versions it was built against
// (`SteamUser019`, `STEAMAPPS_INTERFACE_VERSION008`, …); written to
// `steam_settings/steam_interfaces.txt`, they let the emulator hand an older
// game the versions it expects. gbe_fork's README calls the file "always"
// recommended, and older games can crash on a Steam call without it.
//
// The patterns and their order are the tool's own (tools/generate_interfaces
// in gbe_fork). The tool writes duplicates; this drops them, which the
// emulator doesn't mind.

enum SteamInterfacesScanner {
    static let patterns = [
        #"STEAMAPPS_INTERFACE_VERSION\d+"#,
        #"SteamApps\d+"#,
        #"STEAMAPPLIST_INTERFACE_VERSION\d+"#,
        #"STEAMAPPTICKET_INTERFACE_VERSION\d+"#,
        #"SteamClient\d+"#,
        #"STEAMCONTROLLER_INTERFACE_VERSION"#,
        #"SteamController\d+"#,
        #"SteamFriends\d+"#,
        #"SteamGameServerStats\d+"#,
        #"SteamGameCoordinator\d+"#,
        #"SteamGameServer\d+"#,
        #"STEAMHTMLSURFACE_INTERFACE_VERSION_\d+"#,
        #"STEAMHTTP_INTERFACE_VERSION\d+"#,
        #"SteamInput\d+"#,
        #"STEAMINVENTORY_INTERFACE_V\d+"#,
        #"SteamMatchMakingServers\d+"#,
        #"SteamMatchMaking\d+"#,
        #"SteamMatchGameSearch\d+"#,
        #"SteamParties\d+"#,
        #"STEAMMUSIC_INTERFACE_VERSION\d+"#,
        #"STEAMMUSICREMOTE_INTERFACE_VERSION\d+"#,
        #"SteamNetworkingMessages\d+"#,
        #"SteamNetworkingSockets\d+"#,
        #"SteamNetworkingUtils\d+"#,
        #"SteamNetworking\d+"#,
        #"STEAMPARENTALSETTINGS_INTERFACE_VERSION\d+"#,
        #"STEAMREMOTEPLAY_INTERFACE_VERSION\d+"#,
        #"STEAMREMOTESTORAGE_INTERFACE_VERSION\d+"#,
        #"STEAMSCREENSHOTS_INTERFACE_VERSION\d+"#,
        #"STEAMTIMELINE_INTERFACE_V\d+"#,
        #"STEAMUGC_INTERFACE_VERSION\d+"#,
        #"SteamUser\d+"#,
        #"STEAMUSERSTATS_INTERFACE_VERSION\d+"#,
        #"SteamUtils\d+"#,
        #"STEAMVIDEO_INTERFACE_V\d+"#,
        #"STEAMUNIFIEDMESSAGES_INTERFACE_VERSION\d+"#,
        #"SteamMasterServerUpdater\d+"#,
    ]

    private static let expressions = patterns.map { try! NSRegularExpression(pattern: $0) }

    /// Every interface version named in `dll`, in the tool's order.
    static func interfaces(in dll: Data) -> [String] {
        // Latin-1 maps each byte to one character, so a binary scans as text
        // without any byte being dropped or merged.
        let text = String(decoding: dll.map { UInt16($0) }, as: UTF16.self) as NSString
        var seen = Set<String>()
        var result: [String] = []
        for (pattern, expression) in zip(patterns, expressions) {
            var found = expression
                .matches(in: text as String, range: NSRange(location: 0, length: text.length))
                .map { text.substring(with: $0.range) }
            // Newer SDKs still answer SteamClient() with SteamClient017 and
            // only that, so when it is present the others are noise.
            if pattern == #"SteamClient\d+"#, found.count > 1, found.contains("SteamClient017") {
                found = ["SteamClient017"]
            }
            for name in found where seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }
}
