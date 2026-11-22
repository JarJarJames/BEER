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

    /// Hand over everything the child writes, on a thread of its own, then
    /// call `onEnd` once it has closed the terminal. A pipe reports the end
    /// as an empty read; a terminal reports it as an error (EIO), which
    /// `FileHandle` would raise as an exception, hence plain `read`.
    func read(_ onData: @escaping @Sendable (Data) -> Void, onEnd: @escaping @Sendable () -> Void) {
        let primary = primary
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = Darwin.read(primary, &buffer, buffer.count)
                if count > 0 {
                    onData(Data(buffer[0..<count]))
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            Darwin.close(primary)
            onEnd()
        }
    }

    /// For a child that never started.
    func close() {
        try? child.close()
        Darwin.close(primary)
    }
}
