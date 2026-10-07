import Foundation

enum RuntimeBundle {
    static func candidate(from url: URL, fallbackDisplayName: String? = nil) throws -> RuntimeCandidate {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw RuntimeBundleError.notDirectory
        }

        let manifestURL = url.appendingPathComponent("runtime.json", isDirectory: false)
        let manifest: RuntimeBundleManifest?
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(RuntimeBundleManifest.self, from: data)
        } else {
            manifest = nil
        }

        let entrypoints = try resolvedEntrypoints(for: url, manifest: manifest)
        guard FileManager.default.isExecutableFile(atPath: entrypoints.wine) else {
            throw RuntimeBundleError.missingExecutable(entrypoints.wine)
        }
        if let wineboot = entrypoints.wineboot,
           !FileManager.default.isExecutableFile(atPath: wineboot) {
            throw RuntimeBundleError.missingExecutable(wineboot)
        }
        if let wineserver = entrypoints.wineserver,
           !FileManager.default.isExecutableFile(atPath: wineserver) {
            throw RuntimeBundleError.missingExecutable(wineserver)
        }

        let version = manifest?.version
        let displayName = displayName(
            manifestName: manifest?.name,
            fallback: fallbackDisplayName ?? url.deletingPathExtension().lastPathComponent,
            version: version
        )

        return RuntimeCandidate(
            kind: .gameNativeWine,
            executablePath: entrypoints.wine,
            displayName: displayName,
            bundlePath: url.path,
            version: version,
            entrypoints: entrypoints
        )
    }

    static func candidateIfAvailable(in url: URL, fallbackDisplayName: String? = nil) -> RuntimeCandidate? {
        guard isRuntimeBundle(url) else { return nil }
        return try? candidate(from: url, fallbackDisplayName: fallbackDisplayName)
    }

    static func isRuntimeBundle(_ url: URL) -> Bool {
        let manifestURL = url.appendingPathComponent("runtime.json", isDirectory: false)
        return url.pathExtension == "runtime" || FileManager.default.fileExists(atPath: manifestURL.path)
    }

    private static func resolvedEntrypoints(for bundleURL: URL, manifest: RuntimeBundleManifest?) throws -> RuntimeEntrypoints {
        if let manifest {
            return RuntimeEntrypoints(
                wine: resolve(manifest.entrypoints.wine, relativeTo: bundleURL).path,
                wineboot: manifest.entrypoints.wineboot.map { resolve($0, relativeTo: bundleURL).path },
                wineserver: manifest.entrypoints.wineserver.map { resolve($0, relativeTo: bundleURL).path }
            )
        }

        let binURL = bundleURL.appendingPathComponent("bin", isDirectory: true)
        let wineURL = binURL.appendingPathComponent("wine", isDirectory: false)
        let winebootURL = binURL.appendingPathComponent("wineboot", isDirectory: false)
        let wineserverURL = binURL.appendingPathComponent("wineserver", isDirectory: false)

        return RuntimeEntrypoints(
            wine: wineURL.path,
            wineboot: FileManager.default.fileExists(atPath: winebootURL.path) ? winebootURL.path : nil,
            wineserver: FileManager.default.fileExists(atPath: wineserverURL.path) ? wineserverURL.path : nil
        )
    }

    private static func resolve(_ path: String, relativeTo bundleURL: URL) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return bundleURL.appendingPathComponent(path, isDirectory: false)
    }

    private static func displayName(manifestName: String?, fallback: String, version: String?) -> String {
        let rawName: String
        if let manifestName, !manifestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawName = manifestName
        } else {
            rawName = fallback
        }

        let baseName = rawName.localizedCaseInsensitiveContains("GameNativeWine") || rawName.localizedCaseInsensitiveContains("GameNative Wine")
            ? "GameNative Wine"
            : rawName

        guard let version, !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return baseName
        }
        return "\(baseName) \(version)"
    }
}
