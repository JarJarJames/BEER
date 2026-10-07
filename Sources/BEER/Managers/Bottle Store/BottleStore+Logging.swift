import AppKit
import Foundation

extension BottleStore {
    func reveal(_ bottle: Bottle) {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.prefixURL(for: bottle)])
    }

    func revealLog(_ bottle: Bottle) {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.logsURL(for: bottle)])
    }

    func copyLogToClipboard(_ bottle: Bottle) {
        let text: String
        if let data = try? Data(contentsOf: AppPaths.logsURL(for: bottle)),
           let fileText = String(data: data, encoding: .utf8),
           !fileText.isEmpty {
            text = fileText
        } else {
            text = logs[bottle.id, default: []]
                .map(\.message)
                .joined(separator: "\n")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appendLog("Copied log to clipboard.", bottleID: bottle.id)
    }

    func resetLog(for bottle: Bottle, reason: String) {
        logs[bottle.id] = []
        let url = AppPaths.logsURL(for: bottle)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: url, options: .atomic)
        appendLog("\(reason) at \(Date.formattedLogDate).", bottleID: bottle.id)
    }

    func appendLog(_ message: String, bottleID: Bottle.ID, isError: Bool = false) {
        // Drop the MoltenVK boilerplate (it dumps ~150 "VK_KHR_…" extension
        // lines + GPU-feature lines on every device probe) so the log stays
        // readable and copyable. Keep the version/GPU summary lines.
        let filtered = message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("VK_") { return false }
                if t == "The following 153 Vulkan extensions are supported:" { return false }
                if t.hasPrefix("GPU Family ") || t == "Read-Write Texture Tier 2" { return false }
                if t == "supports the following GPU Features:" { return false }
                return true
            }
            .joined(separator: "\n")
        let trimmed = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logs[bottleID, default: []].append(BottleLogEntry(date: Date(), message: trimmed, isError: isError))
        writeLogLine(trimmed, bottleID: bottleID)
    }

    func loadPersistedLogs() {
        for bottle in bottles {
            let url = AppPaths.logsURL(for: bottle)
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8),
                  !text.isEmpty else {
                continue
            }

            logs[bottle.id] = text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .suffix(500)
                .map { line in
                    BottleLogEntry(date: Date(), message: String(line), isError: line.localizedCaseInsensitiveContains("error") || line.localizedCaseInsensitiveContains("failed"))
                }
        }
    }

    func writeLogLine(_ message: String, bottleID: Bottle.ID) {
        guard let bottle = bottles.first(where: { $0.id == bottleID }) else { return }
        let line = "[\(Date.formattedLogDate)] \(message)\n"
        let url = AppPaths.logsURL(for: bottle)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
