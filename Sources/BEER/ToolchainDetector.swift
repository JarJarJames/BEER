import Foundation

@MainActor
final class ToolchainDetector: ObservableObject {
    @Published private(set) var candidates: [RuntimeCandidate] = []
    @Published private(set) var isRefreshing = false

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var found: [RuntimeCandidate] = []
        let fileManager = FileManager.default

        let fixedCandidates: [(RuntimeKind, String, String)] = [
            (.crossOver, "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64", "CrossOver wine64"),
            (.crossOver, "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine", "CrossOver wine"),
            (.whisky, "/Applications/Whisky.app/Contents/Resources/Libraries/Wine/bin/wine64", "Whisky wine64"),
            (.whisky, "/Applications/Whisky.app/Contents/Resources/Libraries/Wine/bin/wine", "Whisky wine"),
            (.gamePortingToolkit, "/opt/homebrew/bin/gameportingtoolkit", "Game Porting Toolkit"),
            (.gamePortingToolkit, "/usr/local/bin/gameportingtoolkit", "Game Porting Toolkit"),
            (.systemWine, "/opt/homebrew/bin/wine64", "Homebrew wine64"),
            (.systemWine, "/opt/homebrew/bin/wine", "Homebrew wine"),
            (.systemWine, "/usr/local/bin/wine64", "Homebrew wine64"),
            (.systemWine, "/usr/local/bin/wine", "Homebrew wine")
        ]

        for candidate in fixedCandidates where fileManager.isExecutableFile(atPath: candidate.1) {
            found.append(RuntimeCandidate(kind: candidate.0, executablePath: candidate.1, displayName: candidate.2))
        }

        for candidate in ManagedRuntimeScanner.findAll() where !found.contains(where: { $0.executablePath == candidate.executablePath }) {
            found.append(candidate)
        }

        let pathCandidates = await detectFromPath()
        for candidate in pathCandidates where !found.contains(where: { $0.executablePath == candidate.executablePath }) {
            found.append(candidate)
        }

        candidates = found.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private nonisolated func detectFromPath() async -> [RuntimeCandidate] {
        let names = ["wine64", "wine", "gameportingtoolkit"]
        var results: [RuntimeCandidate] = []

        for name in names {
            guard let path = try? await which(name) else { continue }
            let kind: RuntimeKind = name == "gameportingtoolkit" ? .gamePortingToolkit : .systemWine
            results.append(RuntimeCandidate(kind: kind, executablePath: path, displayName: "PATH \(name)"))
        }

        return results
    }

    private nonisolated func which(_ name: String) async throws -> String? {
        let result = try await ShellRunner.run(
            executable: "/usr/bin/which",
            arguments: [name],
            environment: [:],
            outputHandler: { _ in }
        )
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !path.isEmpty ? path : nil
    }
}
