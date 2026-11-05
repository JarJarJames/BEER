import Foundation

extension Bottle {
    /// The Wine this bottle runs is no longer where it was recorded.
    var runtimeIsMissing: Bool {
        !FileManager.default.isExecutableFile(atPath: runtimeEntrypoints?.wine ?? runtimePath)
    }

    /// This bottle's runtime, found again after its files moved within its
    /// folder in `runtimesDirectory`: a re-download that unpacks one folder
    /// deeper, say. nil when the runtime is still where it was recorded, isn't
    /// one BEER manages, or its folder is gone.
    func movedRuntime(in runtimesDirectory: URL) -> RuntimeCandidate? {
        guard runtimeIsMissing else { return nil }
        let root = runtimesDirectory.path + "/"
        guard runtimeLocationPath.hasPrefix(root),
              let folder = runtimeLocationPath.dropFirst(root.count).split(separator: "/").first else { return nil }
        // Named as `ManagedRuntimeScanner.findAll` names it, so the picker matches.
        return ManagedRuntimeScanner.findRuntime(
            in: runtimesDirectory.appendingPathComponent(String(folder), isDirectory: true),
            displayName: "Managed \(folder)"
        )
    }
}
