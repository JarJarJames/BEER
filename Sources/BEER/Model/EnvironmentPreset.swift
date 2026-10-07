import Foundation

/// Environment tweaks that fix a recognised class of breakage, so the fix is a
/// menu item instead of something a user has to already know to type.
struct EnvironmentPreset: Identifiable {
    var id: String { "\(key)=\(value)" }
    let key: String
    let value: String
    let title: String
    let detail: String

    static let all: [EnvironmentPreset] = [
        EnvironmentPreset(
            key: "SDL_GPU_DRIVER", value: "vulkan",
            title: "Force SDL3 games onto Vulkan",
            detail: """
                SDL3's GPU API tries Direct3D 12 first and has no D3D11 fallback.                 DXVK doesn't implement D3D12, so the device comes back null and the                 game usually crashes on startup. This routes it to Vulkan instead.
                """),
        EnvironmentPreset(
            key: "CX_FWD_COMPAT_GL_CTX", value: "1",
            title: "Fix OpenGL games that won't start (GPTK/CrossOver)",
            detail: """
                macOS only hands out forward-compatible OpenGL 3.2+ contexts, and Wine                 rejects any request that doesn't ask for one — which is most games, since                 SDL only sets that flag when told to. The result is a "could not create GL                 context" error on launch. This makes CrossOver's Wine add the flag itself.                 No effect on mainline Wine runtimes, or on games that use Direct3D.
                """),
        EnvironmentPreset(
            key: "SDL_AUDIO_DRIVER", value: "directsound",
            title: "Fix crackling audio in SDL games",
            detail: """
                SDL prefers WASAPI, which crackles under Wine for some games. This routes                 audio through DirectSound instead, which is the same thing CrossOver's                 "set the app to Windows XP" advice achieves — SDL skips WASAPI on XP —                 without changing the Windows version the game sees.
                """),
        EnvironmentPreset(
            key: "MTL_HUD_ENABLED", value: "1",
            title: "Show Metal performance HUD",
            detail: "Apple's frame-rate overlay, drawn by Metal, so it works on any backend."),
        EnvironmentPreset(
            key: "DXVK_HUD", value: "fps",
            title: "Show DXVK frame counter",
            detail: "Only appears when the game is actually running through DXVK."),
        EnvironmentPreset(
            key: "WINEDEBUG", value: "-all",
            title: "Silence Wine debug output",
            detail: "Trims log noise and a little overhead — at the cost of making beer.log much less useful when something breaks."),
    ]
}
