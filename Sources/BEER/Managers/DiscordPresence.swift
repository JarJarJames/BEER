import Darwin
import Foundation

/// Shows the running game on the user's Discord profile.
///
/// The Discord desktop client listens on a Unix socket in `$TMPDIR` and takes
/// Rich Presence from any local app that names a registered application ID —
/// no Discord login involved. Discord drops the card itself when the socket
/// closes, so ending play is just closing it, and a BEER crash can't leave a
/// stale "Playing" behind.
///
/// Best-effort throughout: Discord not running, or refusing the card, is
/// logged and otherwise ignored. All socket work happens on one serial queue.
final class DiscordPresence: @unchecked Sendable {
    static let shared = DiscordPresence()

    private let queue = DispatchQueue(label: "io.github.jarjarjames.beer.discord")
    // Touched only on `queue`.
    private var socket: Int32 = -1
    private var currentAppID: Int?

    func beginPlaying(_ game: SteamLibraryGame) {
        let clientID = DiscordPresenceConfig.applicationID
        guard !clientID.isEmpty else { return }
        let activity = DiscordActivity(game: game, startedAt: Date())
        let pid = ProcessInfo.processInfo.processIdentifier

        queue.async { [self] in
            do {
                let command = try Self.setActivityCommand(activity, pid: pid, nonce: UUID().uuidString)
                if socket < 0 { try connect(clientID: clientID) }
                try send(opcode: .frame, command)
                currentAppID = game.appID
                if let failure = Self.errorMessage(in: try receive()) {
                    Log.discord.error("Discord rejected the activity: \(failure, privacy: .public)")
                }
            } catch {
                Log.discord.info("No Discord presence: \(String(describing: error), privacy: .public)")
                disconnect()
            }
        }
    }

    /// Clears the card, unless another game has taken it over since.
    func endPlaying(appID: Int) {
        queue.async { [self] in
            guard currentAppID == appID else { return }
            disconnect()
        }
    }

    // MARK: - Wire format

    enum Opcode: UInt32 {
        case handshake = 0
        case frame = 1
        case close = 2
    }

    enum Failure: Error {
        case discordNotRunning
        case closedByDiscord(String)
        case io(Int32)
    }

    /// Every message is a little-endian opcode and length, then JSON.
    static func frame(_ opcode: Opcode, _ body: Data) -> Data {
        var data = Data()
        withUnsafeBytes(of: opcode.rawValue.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(body.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(body)
        return data
    }

    static func handshake(clientID: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["v": 1, "client_id": clientID])
    }

    static func setActivityCommand(_ activity: DiscordActivity, pid: Int32, nonce: String) throws -> Data {
        struct Args: Encodable { let pid: Int32; let activity: DiscordActivity }
        struct Command: Encodable { let cmd = "SET_ACTIVITY"; let args: Args; let nonce: String }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(Command(args: Args(pid: pid, activity: activity), nonce: nonce))
    }

    /// Discord answers a bad command with `"evt": "ERROR"` and a message.
    static func errorMessage(in reply: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              object["evt"] as? String == "ERROR" else { return nil }
        let data = object["data"] as? [String: Any]
        return data?["message"] as? String ?? "unknown error"
    }

    // MARK: - Socket

    private func connect(clientID: String) throws {
        let directory = NSTemporaryDirectory()
        guard let fd = DiscordPresenceConfig.socketNames.lazy
            .compactMap({ Self.open(path: (directory as NSString).appendingPathComponent($0)) })
            .first
        else { throw Failure.discordNotRunning }

        socket = fd
        try send(opcode: .handshake, try Self.handshake(clientID: clientID))
        _ = try receive()  // READY
    }

    private func disconnect() {
        if socket >= 0 { close(socket) }
        socket = -1
        currentAppID = nil
    }

    private func send(opcode: Opcode, _ body: Data) throws {
        let bytes = Self.frame(opcode, body)
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(socket, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { throw Failure.io(errno) }
                offset += written
            }
        }
    }

    /// Reads one reply. A close frame means Discord turned the connection down
    /// — most often an unknown application ID.
    private func receive() throws -> Data {
        let header = try read(count: 8)
        let opcode = header.prefix(4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        let length = header.suffix(4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        let body = try read(count: Int(length))
        if opcode == Opcode.close.rawValue {
            throw Failure.closedByDiscord(String(decoding: body, as: UTF8.self))
        }
        return body
    }

    private func read(count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { buffer in
            while offset < count {
                let got = Darwin.read(socket, buffer.baseAddress! + offset, count - offset)
                guard got > 0 else { throw Failure.io(got == 0 ? ECONNRESET : errno) }
                offset += got
            }
        }
        return data
    }

    private static func open(path: String) -> Int32? {
        var address = sockaddr_un()
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            return nil
        }

        // A Discord that quits mid-write must fail the write, not kill BEER
        // with SIGPIPE; and one that stops answering must not hang the queue.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }
}
