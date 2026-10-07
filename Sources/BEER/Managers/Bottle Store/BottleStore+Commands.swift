import AppKit
import Foundation

extension BottleStore {
    func stopBottleProcesses(_ bottle: Bottle) async {
        await runBottleCommand(
            bottle,
            operation: "Stopping bottle processes",
            mode: .winebootKill,
            allowWhileActive: true
        )
    }

    func runBottleCommand(
        _ bottle: Bottle,
        operation: String,
        mode: BottleCommandMode,
        allowWhileActive: Bool = false,
        environmentOverrides: [String: String] = [:],
        workingDirectory: URL? = nil
    ) async {
        guard allowWhileActive || !activeBottleIDs.contains(bottle.id) else { return }

        activeBottleIDs.insert(bottle.id)
        appendLog("\(operation)...", bottleID: bottle.id)

        do {
            try AppPaths.ensureBaseDirectories()
            let prefix = AppPaths.prefixURL(for: bottle)
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)

            let command = command(for: bottle, prefix: prefix, mode: mode)

            // Log the exact command we're about to run so launch configuration
            // issues are diagnosable from beer.log instead of guesswork.
            let renderedArgs = command.arguments
                .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
                .joined(separator: " ")
            appendLog("$ \(command.executable) \(renderedArgs)", bottleID: bottle.id)

            let result = try await ShellRunner.run(
                executable: command.executable,
                arguments: command.arguments,
                environment: environment(for: bottle, prefix: prefix).merging(environmentOverrides) { _, new in new },
                currentDirectory: workingDirectory,
                outputHandler: { [weak self] chunk in
                    Task { @MainActor in
                        self?.appendLog(chunk.trimmingCharacters(in: .newlines), bottleID: bottle.id)
                    }
                }
            )

            if result.exitCode == 0 {
                appendLog("\(operation) finished.", bottleID: bottle.id)
            } else {
                appendLog("\(operation) exited with code \(result.exitCode).", bottleID: bottle.id, isError: true)
            }
        } catch {
            appendLog("\(operation) failed: \(error.localizedDescription)", bottleID: bottle.id, isError: true)
            lastError = error.localizedDescription
        }

        activeBottleIDs.remove(bottle.id)
    }

    func command(for bottle: Bottle, prefix: URL, mode: BottleCommandMode) -> BottleCommand {
        if isRuntimeBundleBottle(bottle) {
            switch mode {
            case .wineboot:
                if let wineboot = runtimeWinebootPath(for: bottle) {
                    return BottleCommand(executable: wineboot, arguments: ["-u"])
                }
                return BottleCommand(executable: runtimeWinePath(for: bottle), arguments: ["wineboot", "-u"])
            case .winebootKill:
                if let wineserver = runtimeWineserverPath(for: bottle) {
                    return BottleCommand(executable: wineserver, arguments: ["-k"])
                }
                if let wineboot = runtimeWinebootPath(for: bottle) {
                    return BottleCommand(executable: wineboot, arguments: ["-k"])
                }
                return BottleCommand(executable: runtimeWinePath(for: bottle), arguments: ["wineboot", "-k"])
            case .wine(let arguments):
                return BottleCommand(executable: runtimeWinePath(for: bottle), arguments: arguments)
            case .executable:
                break
            }
        }

        if bottle.runtimeKind == .gamePortingToolkit {
            switch mode {
            case .wineboot:
                return BottleCommand(executable: bottle.runtimePath, arguments: [prefix.path, "wineboot", "-u"])
            case .winebootKill:
                return BottleCommand(executable: bottle.runtimePath, arguments: [prefix.path, "wineboot", "-k"])
            case .wine(let arguments):
                return BottleCommand(executable: bottle.runtimePath, arguments: [prefix.path] + arguments)
            case .executable:
                break
            }
        }

        switch mode {
        case .wineboot:
            let wineboot = URL(fileURLWithPath: bottle.runtimePath)
                .deletingLastPathComponent()
                .appendingPathComponent("wineboot")
                .path
            if FileManager.default.isExecutableFile(atPath: wineboot) {
                return BottleCommand(executable: wineboot, arguments: ["-u"])
            }
            return BottleCommand(executable: bottle.runtimePath, arguments: ["wineboot", "-u"])
        case .winebootKill:
            let wineboot = URL(fileURLWithPath: bottle.runtimePath)
                .deletingLastPathComponent()
                .appendingPathComponent("wineboot")
                .path
            if FileManager.default.isExecutableFile(atPath: wineboot) {
                return BottleCommand(executable: wineboot, arguments: ["-k"])
            }
            return BottleCommand(executable: bottle.runtimePath, arguments: ["wineboot", "-k"])
        case .wine(let arguments):
            return BottleCommand(executable: bottle.runtimePath, arguments: arguments)
        case .executable(let path, let arguments):
            return BottleCommand(executable: path, arguments: arguments)
        }
    }
}
