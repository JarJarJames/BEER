import Foundation

/// Where the Runtimes tab finds Wine and GPTK builds to download.
enum RuntimeSources {
    /// BEER's own GPTK builds: CrossOver's open-source Wine with Apple's
    /// D3DMetal, made by scripts/build_gptk_runtime.sh. Listed first.
    static let beerGPTKReleases = URL(string: "https://api.github.com/repos/JarJarJames/BEER-runtimes/releases?per_page=10")!
    /// Apple's D3DMetal 4 runs on macOS 15 or later, so older Macs get
    /// Gcenx's GPTK instead.
    static let beerGPTKMinimumMacOS = 15

    static let gcenxGPTKReleases = URL(string: "https://api.github.com/repos/Gcenx/game-porting-toolkit/releases?per_page=30")!
    static let gcenxWineBuilds = URL(string: "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases?per_page=8")!
}
