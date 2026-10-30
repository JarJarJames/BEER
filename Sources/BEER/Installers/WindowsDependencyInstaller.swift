import Foundation

// Installs Microsoft runtimes (VC++, DirectX) into a game's bottle — the
// handful of winetricks verbs games actually ask for, without winetricks.
//
// Why not shell out to winetricks against the bottle's Wine: it would mean
// fetching the script from GitHub, needing Homebrew's cabextract for most
// verbs, and downloading through `aka.ms` shortlinks whose hashes go stale
// whenever Microsoft ships an update. Instead we download pinned files from
// Microsoft (`WindowsDependencyManifest`), check them by SHA-256, and run
// Microsoft's own installers through `BottleStore`, so they get the bottle's
// runtime and environment (Wine user `crossover`) like everything else.
// The Wine-specific steps are lifted from winetricks' vcrun2026 / directx verbs.
@MainActor
final class WindowsDependencyInstaller: ObservableObject {
    struct Job: Equatable {
        let bottleID: Bottle.ID
        let dependency: WindowsDependency
    }

    @Published private(set) var installed: [Bottle.ID: Set<WindowsDependency>] = [:]
    @Published private(set) var busy: Job?
    @Published private(set) var statusMessage: [Bottle.ID: String] = [:]
    @Published private(set) var lastError: [Bottle.ID: String] = [:]

    /// Scratch space inside the prefix for things Windows tools need a C:
    /// path for. Free of spaces, unlike Application Support.
    static let windowsTempPath = #"C:\windows\temp"#
    static let prefixTempPath = "drive_c/windows/temp"

    func refresh(_ bottle: Bottle) {
        installed[bottle.id] = WindowsDependencyDetector.installed(inPrefix: AppPaths.prefixURL(for: bottle))
    }

    func install(_ dependency: WindowsDependency, into bottle: Bottle, using bottles: BottleStore) async {
        guard busy == nil else { return }
        busy = Job(bottleID: bottle.id, dependency: dependency)
        lastError[bottle.id] = nil
        defer { busy = nil }

        do {
            guard !bottles.activeBottleIDs.contains(bottle.id) else { throw WindowsDependencyError.bottleBusy }
            let prefix = AppPaths.prefixURL(for: bottle)

            var files: [(RedistributablePackage, URL)] = []
            for package in dependency.packages {
                files.append((package, try await ensureDownloaded(package, bottleID: bottle.id)))
            }

            switch dependency {
            case .vcRedist:
                setStatus(WindowsDependencyStrings.preparing, bottle)
                try Self.removeWinePlaceholders(WindowsDependencyManifest.vcRedistPlaceholderDLLs, inPrefix: prefix)
                for (package, file) in files {
                    try await run(package, executable: file.path, bottle: bottle, bottles: bottles)
                }
                setStatus(WindowsDependencyStrings.applyingOverrides, bottle)
                guard await bottles.applyNativeDLLOverrides(WindowsDependencyManifest.vcRedistDLLOverrides, to: bottle) else {
                    throw WindowsDependencyError.installerFailed(file: "regedit", exitCode: nil)
                }
                guard WindowsDependencyDetector.hasNativeDLLs(for: .vcRedist, inPrefix: prefix) else {
                    throw WindowsDependencyError.notDetectedAfterInstall(dependency.title)
                }
            case .directX:
                for (package, file) in files {
                    try await installDirectX(package, archive: file, prefix: prefix, bottle: bottle, bottles: bottles)
                }
            }

            try recordReceipt(dependency, inPrefix: prefix)
            refresh(bottle)
            setStatus(WindowsDependencyStrings.finished(dependency), bottle)
            bottles.appendLog(WindowsDependencyStrings.finished(dependency), bottleID: bottle.id)
        } catch {
            lastError[bottle.id] = error.localizedDescription
            setStatus(WindowsDependencyStrings.failed, bottle)
            bottles.appendLog("\(dependency.title): \(error.localizedDescription)", bottleID: bottle.id, isError: true)
            refresh(bottle)
        }
    }

    // MARK: - Download + verify

    /// The cached, hash-verified file for `package`, downloading it if the
    /// cache is missing or doesn't match. A file that fails the check is
    /// deleted and never run.
    private func ensureDownloaded(_ package: RedistributablePackage, bottleID: Bottle.ID) async throws -> URL {
        let directory = AppPaths.dependenciesDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(package.fileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            statusMessage[bottleID] = WindowsDependencyStrings.verifying(package.fileName)
            if (try? SHA256Digest.fileHexDigest(destination)) == package.sha256 { return destination }
            try FileManager.default.removeItem(at: destination)
        }

        guard package.isFromOfficialHost else {
            throw WindowsDependencyError.unofficialSource(package.url.host ?? package.url.absoluteString)
        }
        statusMessage[bottleID] = WindowsDependencyStrings.downloading(package.fileName, size: package.size)
        let (tempURL, response) = try await URLSession.shared.download(from: package.url)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw WindowsDependencyError.downloadFailed(package.fileName)
        }

        statusMessage[bottleID] = WindowsDependencyStrings.verifying(package.fileName)
        let actual = try SHA256Digest.fileHexDigest(tempURL)
        guard actual == package.sha256 else {
            throw WindowsDependencyError.checksumMismatch(file: package.fileName, expected: package.sha256, actual: actual)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    // MARK: - Running installers

    private func run(
        _ package: RedistributablePackage,
        executable: String,
        extraArguments: [String] = [],
        bottle: Bottle,
        bottles: BottleStore
    ) async throws {
        try await run(
            label: package.fileName,
            arguments: [executable] + package.installArguments + extraArguments,
            succeeded: package.isSuccess(exitCode:),
            bottle: bottle,
            bottles: bottles
        )
    }

    private func run(
        label: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        succeeded: (Int32) -> Bool = { $0 == 0 },
        bottle: Bottle,
        bottles: BottleStore
    ) async throws {
        setStatus(WindowsDependencyStrings.running(label), bottle)
        let exitCode = await bottles.runBottleCommand(
            bottle,
            operation: "Running \(label)",
            mode: .wine(arguments: arguments),
            workingDirectory: workingDirectory
        )
        // MSI work continues in msiexec after the bootstrapper returns; let the
        // prefix go idle before the next step looks at the files.
        await bottles.waitForWineSessionExit(bottle)
        guard let exitCode, succeeded(exitCode) else {
            throw WindowsDependencyError.installerFailed(file: label, exitCode: exitCode)
        }
    }

    /// Unpack the IExpress archive into the prefix, then run the DXSETUP
    /// inside it. DXSETUP needs its cabinets beside it, so it runs from there.
    private func installDirectX(
        _ package: RedistributablePackage,
        archive: URL,
        prefix: URL,
        bottle: Bottle,
        bottles: BottleStore
    ) async throws {
        let folder = "beer-directx"
        let unpacked = prefix.appendingPathComponent(Self.prefixTempPath).appendingPathComponent(folder)
        try? FileManager.default.removeItem(at: unpacked)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unpacked) }

        let target = Self.windowsTempPath + #"\"# + folder
        try await run(package, executable: archive.path, extraArguments: ["/T:\(target)"], bottle: bottle, bottles: bottles)
        try await run(
            label: "DXSETUP.exe",
            arguments: [target + #"\DXSETUP.exe"#, "/silent"],
            workingDirectory: unpacked,
            bottle: bottle,
            bottles: bottles
        )
    }

    /// Clear Wine's own copies of DLLs a Microsoft installer is about to put
    /// down, keyed by prefix-relative directory (see
    /// `WindowsDependencyManifest.vcRedistPlaceholderDLLs`). Only Wine's copies
    /// are removed — a real Microsoft DLL is left alone. Wine still loads its
    /// builtin without the file, and Repair Prefix puts them back.
    static func removeWinePlaceholders(_ placeholders: [String: [String]], inPrefix prefix: URL) throws {
        for (directory, names) in placeholders {
            for name in names {
                let url = prefix.appendingPathComponent(directory).appendingPathComponent(name)
                if WindowsDependencyDetector.isWineBuiltin(url) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    /// A `.reg` file setting each DLL to native-then-builtin — what winetricks'
    /// `w_override_dlls native,builtin` writes.
    static func dllOverrideRegistry(_ dlls: [String]) -> String {
        var lines = ["REGEDIT4", "", #"[HKEY_CURRENT_USER\Software\Wine\DllOverrides]"#]
        lines += dlls.map { "\"\($0)\"=\"native,builtin\"" }
        return lines.joined(separator: "\n") + "\n"
    }

    private func recordReceipt(_ dependency: WindowsDependency, inPrefix prefix: URL) throws {
        let url = prefix.appendingPathComponent(WindowsDependencyDetector.receiptFileName)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try WindowsDependencyDetector.receipt(byAdding: dependency, to: existing)
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private func setStatus(_ message: String, _ bottle: Bottle) {
        statusMessage[bottle.id] = message
    }
}
