import AppKit
import Darwin
import Foundation

/// Whether a bottle has a window on screen: the signal that takes the launch
/// status from "Starting game…" to "Playing".
///
/// Wine's Mac driver starts every process as a background one and turns it
/// into a regular, Dock-showing app the first time it orders a window in
/// (`transformProcessToForeground`, called from `-[WineWindow
/// orderBelow:orAbove:activate:]` in winemac.drv's cocoa_window.m). Services,
/// winedevice and explorer never show a window, so they never turn regular.
///
/// The process that shows the window is often not the one BEER started: games
/// hand off to a child, and Wine double-forks children, so they aren't BEER's
/// descendants. They do inherit the Unix environment unchanged (ntdll's
/// `spawn_process` execs with the parent's `environ`), and BEER always sets
/// `WINEPREFIX` to the bottle's prefix. A regular app whose `WINEPREFIX` is the
/// bottle's is therefore a window in that bottle.
enum WineWindowProbe {
    @MainActor
    static func hasWindow(inPrefix prefix: URL) -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let regularPIDs = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
            .map(\.processIdentifier)
        return containsProcess(in: prefix, among: regularPIDs, environment: environment(of:))
    }

    /// Whether any of `pids` runs with `WINEPREFIX` set to `prefix`.
    static func containsProcess(in prefix: URL, among pids: [pid_t], environment: (pid_t) -> [String]?) -> Bool {
        let target = prefix.standardizedFileURL.path
        return pids.contains { pid in
            guard let value = environment(pid).flatMap({ value(of: "WINEPREFIX", in: $0) }) else { return false }
            return URL(fileURLWithPath: value).standardizedFileURL.path == target
        }
    }

    static func value(of name: String, in environment: [String]) -> String? {
        let key = name + "="
        return environment.first { $0.hasPrefix(key) }.map { String($0.dropFirst(key.count)) }
    }

    /// Another process's environment, from `KERN_PROCARGS2`. macOS allows it
    /// for the same user's processes, but hides it for the system's own
    /// binaries; Wine isn't one. Nil when it can't be read, as for a process
    /// that has just exited.
    static func environment(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return environment(fromProcArgs: Array(buffer.prefix(size)))
    }

    /// `KERN_PROCARGS2` is: argc (Int32), the executable path, NUL padding,
    /// argc NUL-terminated arguments, then the environment and, after it,
    /// Apple's own `key=value` strings, which never name a Wine variable.
    static func environment(fromProcArgs bytes: [UInt8]) -> [String]? {
        let countSize = MemoryLayout<Int32>.size
        guard bytes.count > countSize else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = countSize

        // The executable path, then the padding after it.
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        // Arguments may be empty strings, so count terminators, not words.
        var argumentsLeft = Int(argc)
        while argumentsLeft > 0, index < bytes.count {
            if bytes[index] == 0 { argumentsLeft -= 1 }
            index += 1
        }
        guard argumentsLeft == 0 else { return nil }

        return bytes[index...]
            .split(separator: 0)
            .map { String(decoding: $0, as: UTF8.self) }
    }
}
