import Foundation

/// A pseudo-terminal to run a child process in, for a program that only
/// reports some things when it thinks a person is watching: DepotDownloader
/// sends its per-chunk progress only to a terminal (see
/// `DepotDownloaderOutput`).
final class PseudoTerminal: @unchecked Sendable {
    /// The child's end: its stdin, stdout and stderr.
    let child: FileHandle
    private let primary: Int32

    init() throws {
        var primary: Int32 = 0
        var secondary: Int32 = 0
        // Wide, so nothing a terminal-aware program prints is wrapped.
        var size = winsize(ws_row: 50, ws_col: 500, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primary, &secondary, nil, nil, &size) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        self.primary = primary
        child = FileHandle(fileDescriptor: secondary, closeOnDealloc: true)
    }

    /// Once the child is running: close this process's copy of its end, so
    /// reading ends when the child exits.
    func childStarted() {
        try? child.close()
    }

    /// Hand over everything the child writes as text, on a thread of its
    /// own, then call `onEnd` once it has closed the terminal. A pipe reports
    /// the end as an empty read; a terminal reports it as an error (EIO),
    /// which `FileHandle` would raise as an exception, hence plain `read`.
    func read(_ onText: @escaping @Sendable (String) -> Void, onEnd: @escaping @Sendable () -> Void) {
        let primary = primary
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var bytes: [UInt8] = []
            while true {
                let count = Darwin.read(primary, &buffer, buffer.count)
                if count > 0 {
                    bytes += buffer[0..<count]
                    // A character split across two reads waits for its rest.
                    let whole = bytes.count - Self.unfinishedCharacter(at: bytes)
                    onText(String(decoding: bytes[0..<whole], as: UTF8.self))
                    bytes.removeFirst(whole)
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            if !bytes.isEmpty { onText(String(decoding: bytes, as: UTF8.self)) }
            Darwin.close(primary)
            onEnd()
        }
    }

    /// How many bytes at the end of `bytes` begin a UTF-8 character whose
    /// remaining bytes haven't arrived yet.
    static func unfinishedCharacter(at bytes: [UInt8]) -> Int {
        var lead = bytes.count - 1
        while lead >= 0, bytes.count - lead < 4, bytes[lead] & 0xC0 == 0x80 { lead -= 1 }
        guard lead >= 0 else { return 0 }
        let length = switch bytes[lead] {
        case 0xF0...: 4
        case 0xE0...: 3
        case 0xC0...: 2
        default: 1
        }
        let arrived = bytes.count - lead
        return arrived < length ? arrived : 0
    }

    /// For a child that never started.
    func close() {
        try? child.close()
        Darwin.close(primary)
    }
}
