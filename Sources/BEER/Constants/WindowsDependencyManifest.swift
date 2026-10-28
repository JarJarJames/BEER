import Foundation

/// Pinned Microsoft downloads for each `WindowsDependency`.
///
/// URLs are the versioned `download.visualstudio.microsoft.com` /
/// `download.microsoft.com` paths, not the `aka.ms` shortlinks: the shortlinks
/// always serve the newest build, so a pinned hash against them breaks the
/// day Microsoft ships an update (winetricks re-pins vcrun every few months
/// for this reason). The versioned paths never change, and for VC++ Microsoft
/// embeds the file's SHA-256 in the path itself. Hashes match winetricks'.
///
/// To update VC++: resolve https://aka.ms/vc14/vc_redist.x64.exe (and .x86),
/// take the redirected URL, and use the hash from its path and the new size.
enum WindowsDependencyManifest {
    static let vcRedistX86 = RedistributablePackage(
        fileName: "VC_redist.x86.exe",
        url: URL(string: "https://download.visualstudio.microsoft.com/download/pr/6ad63323-a427-4c58-8464-9f1f19f62359/F0BAB33A302B3CDB2E11113760D016F54FD3D2632C65BA7834FAC4F0ABD7F1A3/VC_redist.x86.exe")!,
        sha256: "f0bab33a302b3cdb2e11113760d016f54fd3d2632c65ba7834fac4f0abd7f1a3",
        size: 6_941_536,
        installArguments: ["/install", "/quiet", "/norestart"],
        successExitCodes: [0, 1638, 3010]
    )

    static let vcRedistX64 = RedistributablePackage(
        fileName: "VC_redist.x64.exe",
        url: URL(string: "https://download.visualstudio.microsoft.com/download/pr/ebdab8e5-1d7b-4d9f-a11b-cbb1720c3b12/843068991DAAA1F73AD9F6239BCE4D0F6A07A51F18C37EA2A867E9BECA71295C/VC_redist.x64.exe")!,
        sha256: "843068991daaa1f73ad9f6239bce4d0f6a07a51f18c37ea2a867e9beca71295c",
        size: 18_731_856,
        installArguments: ["/install", "/quiet", "/norestart"],
        successExitCodes: [0, 1638, 3010]
    )

    /// An IExpress self-extractor: `/Q /C /T:<dir>` unpacks it silently, and
    /// the `DXSETUP.exe /silent` inside does the install (see the installer).
    static let directXJune2010 = RedistributablePackage(
        fileName: "directx_Jun2010_redist.exe",
        url: URL(string: "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe")!,
        sha256: "053f76dcbb28802e23341b6a787e3b0791c0fa5c8d4d011b1044172dbf89c73b",
        size: 100_275_120,
        installArguments: ["/Q", "/C"],
        successExitCodes: [0]
    )

    static func packages(for dependency: WindowsDependency) -> [RedistributablePackage] {
        switch dependency {
        // x86 first, matching winetricks: the 32-bit runtime is the one older
        // launchers need, and it doesn't depend on the 64-bit one.
        case .vcRedist: [vcRedistX86, vcRedistX64]
        case .directX: [directXJune2010]
        }
    }

    /// Runtime DLLs the VC++ redist ships. Wine prefers its own builtins for
    /// these, so after installing we flip them to native-first — otherwise the
    /// install lands on disk and nothing loads it.
    static let vcRedistDLLOverrides = [
        "concrt140", "msvcp140", "msvcp140_1", "msvcp140_2", "msvcp140_atomic_wait",
        "msvcp140_codecvt_ids", "vcamp140", "vccorlib140", "vcomp140", "vcruntime140",
        "vcruntime140_1",
    ]

    /// Wine's builtin copies carry a higher version than Microsoft's, so the
    /// MSI skips them and leaves Wine's in place (Wine bug 57518). Clearing
    /// these placeholders first lets the real files land. Keyed by the
    /// prefix-relative Windows system directory.
    static let vcRedistPlaceholderDLLs: [String: [String]] = [
        "drive_c/windows/syswow64": ["msvcp140.dll", "msvcp140_2.dll"],
        "drive_c/windows/system32": ["msvcp140.dll", "msvcp140_2.dll", "vcruntime140_1.dll"],
    ]

    /// The runtime DLLs of the VC++ year Steam installs from
    /// `_CommonRedist/vcredist/<year>`, flipped to native-first afterwards for
    /// the same reason as `vcRedistDLLOverrides`. 2005 and 2008 install into
    /// WinSxS, which Wine resolves by manifest, so they need nothing.
    static func steamVCRuntimeDLLs(year: String) -> [String] {
        switch year {
        case "2010": ["msvcp100", "msvcr100", "mfc100", "mfc100u", "vcomp100", "atl100"]
        case "2012": ["msvcp110", "msvcr110", "mfc110", "mfc110u", "vcomp110", "atl110"]
        case "2013": ["msvcp120", "msvcr120", "mfc120", "mfc120u", "vcomp120"]
        case "2015", "2017", "2019", "2022": vcRedistDLLOverrides
        default: []
        }
    }

    /// Wine's copies to clear before that year's installer runs. Before VC++
    /// 14 the whole set goes: Wine stamps some with Microsoft's exact version
    /// (msvcr120 is 12.0.40664.0 in both), and the MSI skips an equal version.
    static func steamVCPlaceholderDLLs(year: String) -> [String: [String]] {
        let dlls = steamVCRuntimeDLLs(year: year)
        if dlls == vcRedistDLLOverrides { return vcRedistPlaceholderDLLs }
        let files = dlls.map { $0 + ".dll" }
        return ["drive_c/windows/syswow64": files, "drive_c/windows/system32": files]
    }
}
