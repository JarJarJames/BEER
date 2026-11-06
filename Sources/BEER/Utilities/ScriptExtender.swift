import Foundation

/// Script extenders a game can have installed beside its exe. Their own loader
/// (f4se_loader.exe) can't start the game past SteamStub, so the Steam
/// emulator's loader loads BEER's starter into the game instead, which starts
/// the extender the same way (Tools/WindowsHelpers/xse_start.c).
enum ScriptExtender {
    /// The extender's loader, and the prefix of the DLL it loads
    /// (`f4se_1_11_240.dll`).
    private static let known = [(loader: "f4se_loader.exe", prefix: "f4se")]

    /// The prefix of the extender installed in `folder`, if any.
    static func prefix(in folder: URL) -> String? {
        let names = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).map { $0.lowercased() })
        return known.first { names.contains($0.loader) }?.prefix
    }
}
