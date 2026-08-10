import AppKit
import SwiftUI

struct RuntimeMenuView: View {
    @EnvironmentObject private var detector: ToolchainDetector
    @Binding var bottle: Bottle
    @Binding var selectedRuntimeID: RuntimeCandidate.ID?
    @Binding var runtimeSelectionError: String?
    let isBusy: Bool

    private var runtimeOptions: [RuntimeCandidate] {
        let current = RuntimeCandidate(
            kind: bottle.runtimeKind,
            executablePath: bottle.runtimePath,
            displayName: bottle.runtimeLabel,
            bundlePath: bottle.runtimeBundlePath,
            version: bottle.runtimeVersion,
            entrypoints: bottle.runtimeEntrypoints
        )
        var options = detector.candidates
        if !options.contains(where: { $0.id == current.id }) {
            options.insert(current, at: 0)
        }
        return options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Menu {
                    ForEach(runtimeOptions) { runtime in
                        Button {
                            selectRuntime(runtime)
                        } label: {
                            Text(runtime.displayName)
                        }
                    }

                    Divider()

                    Button {
                        chooseRuntimeForBottle()
                    } label: {
                        Text("Choose manually...")
                    }
                } label: {
                    Label(bottle.runtimeLabel, systemImage: "wineglass")
                        .frame(width: 260, alignment: .leading)
                }
                .menuStyle(.button)
                .disabled(isBusy)

                Button {
                    Task {
                        await detector.refresh()
                        selectedRuntimeID = bottle.runtimeLocationPath
                    }
                } label: {
                    Label("Refresh Runtimes", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(isBusy || detector.isRefreshing)
            }

            Text(bottle.runtimeLocationPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            if let runtimeSelectionError {
                Text(runtimeSelectionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selectRuntime(_ runtime: RuntimeCandidate) {
        bottle.useRuntime(runtime)
        selectedRuntimeID = runtime.id
        runtimeSelectionError = nil
    }

    private func chooseRuntimeForBottle() {
        let previousID = bottle.runtimeLocationPath
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Select a Wine executable or a GameNative .runtime bundle directory."

        guard panel.runModal() == .OK, let url = panel.url else {
            selectedRuntimeID = previousID
            return
        }

        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            let runtime: RuntimeCandidate
            if values.isDirectory == true {
                runtime = try RuntimeBundle.candidate(from: url)
            } else {
                guard FileManager.default.isExecutableFile(atPath: url.path) else {
                    runtimeSelectionError = "The selected file is not executable."
                    selectedRuntimeID = previousID
                    return
                }
                runtime = RuntimeCandidate(
                    kind: .custom,
                    executablePath: url.path,
                    displayName: url.lastPathComponent
                )
            }

            bottle.useRuntime(runtime)
            selectedRuntimeID = runtime.id
            runtimeSelectionError = nil
        } catch {
            selectedRuntimeID = previousID
            runtimeSelectionError = error.localizedDescription
        }
    }
}



