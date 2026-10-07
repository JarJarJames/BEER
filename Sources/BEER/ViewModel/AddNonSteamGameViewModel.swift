import Foundation

/// State and actions behind the "Add Non-Steam Game" sheet: pick a game folder
/// and its executable, bring the folder into a fresh GPTK bottle's
/// `drive_c/Games` (move or copy), and register it in the library.
@MainActor
final class AddNonSteamGameViewModel: ObservableObject {
    @Published private(set) var folder: URL?
    @Published var name: String = ""
    @Published private(set) var executables: [URL] = []
    @Published var selectedExecutable: URL?
    @Published var transferMode: GameFolderTransfer.Mode = .move
    @Published private(set) var imageURL: URL?
    @Published private(set) var isScanning = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let bottles: BottleStore
    private let library: SteamLibraryStore
    private let detector: ToolchainDetector

    init(bottles: BottleStore, library: SteamLibraryStore, detector: ToolchainDetector) {
        self.bottles = bottles
        self.library = library
        self.detector = detector
    }

    var canAdd: Bool {
        folder != nil && selectedExecutable != nil && !trimmedName.isEmpty
            && detector.preferredGameRuntime != nil && !isWorking
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var hasRuntime: Bool { detector.preferredGameRuntime != nil }

    func setFolder(_ url: URL) {
        folder = url
        if trimmedName.isEmpty { name = url.lastPathComponent }
        executables = []
        selectedExecutable = nil
        isScanning = true
        let gameName = trimmedName
        Task { [weak self] in
            // Walks the whole folder, which can be tens of thousands of files.
            let found = await Task.detached {
                LaunchExecutableFinder.rankedExecutables(in: url, gameName: gameName)
            }.value
            guard let self, self.folder == url else { return }
            self.executables = found
            self.selectedExecutable = found.first
            self.isScanning = false
        }
    }

    /// An executable the scan missed (or skipped as an installer-looking name).
    func addExecutable(_ url: URL) {
        if !executables.contains(url) { executables.insert(url, at: 0) }
        selectedExecutable = url
    }

    func setImage(_ url: URL?) { imageURL = url }

    /// Path of `exe` relative to the game folder, for display.
    func relativePath(of exe: URL) -> String {
        guard let folder else { return exe.lastPathComponent }
        let root = folder.standardizedFileURL.path
        let path = exe.standardizedFileURL.path
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }

    /// Returns true when the game was added.
    func add() async -> Bool {
        guard let folder, let exe = selectedExecutable,
              let runtime = detector.preferredGameRuntime, canAdd else { return false }
        isWorking = true
        defer { isWorking = false }

        let gameName = trimmedName
        let bottle = await bottles.createBottle(name: gameName, runtime: runtime, graphicsBackend: .automatic)
        let destination = AppPaths.prefixURL(for: bottle)
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("Games", isDirectory: true)
            .appendingPathComponent(gameName.safeGameFolderName, isDirectory: true)

        do {
            let mode = transferMode
            try await Task.detached {
                try GameFolderTransfer.transfer(from: folder, to: destination, mode: mode)
            }.value
        } catch {
            // Nothing was transferred (the source is left alone on failure), so
            // the still-empty bottle is safe to discard.
            await bottles.delete(bottle)
            errorMessage = "Couldn't bring the game folder in: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            return false
        }

        let launchExe = GameFolderTransfer.relocated(exe, from: folder, to: destination)
        await bottles.recordNonSteamInstall(bottle, launchExecutable: launchExe.path, installDirectory: destination.path)

        // The game is in and launchable; art is cosmetic, so a failed copy
        // doesn't undo any of that.
        let artPath = imageURL.flatMap { copyArt($0, for: bottle.id) }
        library.addNonSteamGame(name: gameName, bottleID: bottle.id, customImagePath: artPath)
        return true
    }

    private func copyArt(_ source: URL, for bottleID: UUID) -> String? {
        let fm = FileManager.default
        let target = AppPaths.customArtDirectory
            .appendingPathComponent("\(bottleID.uuidString).\(source.pathExtension.lowercased().ifEmpty(default: "png"))")
        do {
            try fm.createDirectory(at: AppPaths.customArtDirectory, withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: source, to: target)
            return target.path
        } catch {
            return nil
        }
    }
}
