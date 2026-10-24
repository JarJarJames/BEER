import Foundation

/// A Windows prerequisite BEER can install into a game's bottle, the way
/// winetricks verbs do — but downloaded only from Microsoft and checked
/// against a pinned SHA-256 (see `WindowsDependencyManifest`).
enum WindowsDependency: String, CaseIterable, Identifiable, Sendable {
    /// Visual C++ 2015–2026 (v14) runtime, both architectures. One installer
    /// pair covers every game built with VS 2015 or later.
    case vcRedist
    /// DirectX End-User Runtime (June 2010): d3dx9/10/11, XAudio2, XACT,
    /// XInput 1.1–1.3 and friends that Windows itself never shipped.
    case directX

    var id: String { rawValue }

    var title: String { WindowsDependencyStrings.title(for: self) }
    var detail: String { WindowsDependencyStrings.detail(for: self) }

    /// The verified downloads this dependency installs, in install order.
    var packages: [RedistributablePackage] { WindowsDependencyManifest.packages(for: self) }

    /// winetricks verbs that install the same thing. A bottle someone already
    /// ran winetricks on records them in `winetricks.log`, so we count those
    /// as installed rather than offering to install them again.
    var winetricksVerbs: Set<String> {
        switch self {
        case .vcRedist: ["vcrun2015", "vcrun2017", "vcrun2019", "vcrun2022", "vcrun2026"]
        case .directX: ["d3dx9", "d3dx10", "d3dx11_43", "xact", "xinput"]
        }
    }
}
