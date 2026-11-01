import Foundation

/// The two facts BEER needs from a Windows .exe header: its bitness, and
/// whether Steam's DRM wrapper (SteamStub) is on it. SteamStub adds a `.bind`
/// section that checks for a running Steam client before the game starts, and
/// quits when none is found — the Steam emulator in `steam_api.dll` is loaded
/// too late to answer it.
struct PortableExecutable: Equatable {
    let is64Bit: Bool
    let sectionNames: [String]

    var isSteamStubWrapped: Bool { sectionNames.contains(".bind") }

    init?(contentsOf url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Headers and the section table sit well inside the first 4 KB.
        guard let data = try? handle.read(upToCount: 4096) else { return nil }
        self.init(header: data)
    }

    init?(header data: Data) {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int? {
            at + 2 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : nil
        }
        func u32(_ at: Int) -> Int? {
            guard let lo = u16(at), let hi = u16(at + 2) else { return nil }
            return lo | hi << 16
        }

        guard bytes.starts(with: [0x4D, 0x5A]),                       // "MZ"
              let pe = u32(0x3C), bytes.count >= pe + 24,
              bytes[pe..<pe + 4].elementsEqual([0x50, 0x45, 0, 0]),   // "PE\0\0"
              let machine = u16(pe + 4),
              let sectionCount = u16(pe + 6),
              let optionalHeaderSize = u16(pe + 20) else { return nil }

        var names: [String] = []
        let table = pe + 24 + optionalHeaderSize
        for index in 0..<sectionCount {
            let start = table + index * 40
            guard start + 8 <= bytes.count else { return nil }
            let raw = bytes[start..<start + 8].prefix { $0 != 0 }
            names.append(String(decoding: raw, as: UTF8.self))
        }
        is64Bit = machine == 0x8664
        sectionNames = names
    }
}
