import Foundation

/// Makes game controllers work in Wine — any mix of them at once.
///
/// Wine's controller driver (`winebus`) has two ways to read a pad, and only
/// one of them works for every kind:
///
/// - Its raw HID bus only turns Xbox pads into XInput devices. It always takes
///   DualShock 4 and DualSense pads, but never as XInput, so an XInput game
///   sees no PlayStation pad at all. And by default it drops pads it doesn't
///   know, Steam's virtual pad among them.
/// - Its SDL bus presents every pad SDL knows as an XInput-style gamepad, but
///   Wine drops SDL's copy of any pad the raw bus already took.
///
/// So BEER turns the raw bus off (`DisableHidraw`) and every pad goes through
/// SDL. SDL skips Steam's virtual pads unless the app runs under Steam, which
/// `allowSteamVirtualGamepadVariable` overrides.
///
/// GPTK's own SDL is built with Apple's GameController framework, which then
/// claims Xbox One/Series pads, and GameController doesn't deliver input to
/// Wine's background driver process, so those pads never reach a game. BEER
/// gives Wine its own SDL build without it (`scripts/build_sdl.sh`), placed
/// beside `winebus.so`: Wine loads SDL by bare name, and `winebus.so` searches
/// its own folder before the runtime's copy, so no runtime file is replaced.
enum ControllerSupport {
    static let allowSteamVirtualGamepadVariable = "SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD"

    static let sdlLibraryName = "libSDL2-2.0.0.dylib"

    /// A shipped .app bundles BEER's SDL; a `swift run` build uses what
    /// `scripts/build_sdl.sh` installed into Application Support.
    static var sdlLibraryURL: URL? {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent(sdlLibraryName), AppPaths.sdlLibraryURL]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The folder holding the runtime's 64-bit `winebus.so`, whose own
    /// directory SDL is looked up in first. Every runtime BEER installs keeps
    /// it at the same place under its Wine root.
    static func winebusDirectory(wineRoot: URL) -> URL? {
        let directory = wineRoot.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        let winebus = directory.appendingPathComponent("winebus.so")
        return FileManager.default.fileExists(atPath: winebus.path) ? directory : nil
    }

    /// Put `library` beside the runtime's `winebus.so`, unless an identical
    /// copy is already there.
    static func installSDL(_ library: URL, into winebusDirectory: URL) throws {
        let destination = winebusDirectory.appendingPathComponent(sdlLibraryName)
        if FileManager.default.contentsEqual(atPath: library.path, andPath: destination.path) { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: library, to: destination)
    }
}
