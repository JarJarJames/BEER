import AppKit
import SwiftUI

struct CreateBottleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector
    @State private var name = "Steam Bottle"
    @State private var selectedRuntimeID: RuntimeCandidate.ID?
    @State private var customRuntime: RuntimeCandidate?
    @State private var customRuntimeError: String?
    @State private var graphicsBackend: GraphicsBackend = .automatic

    private var customRuntimeID: String { "custom-runtime" }

    private var selectedRuntime: RuntimeCandidate? {
        if selectedRuntimeID == customRuntimeID {
            return customRuntime
        }

        let id = selectedRuntimeID ?? detector.candidates.first?.id
        return detector.candidates.first { $0.id == id }
    }

    private var canCreate: Bool {
        selectedRuntime != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Bottle")
                .font(.title2.bold())

            Form {
                TextField("Name", text: $name)

                if detector.candidates.isEmpty {
                    LabeledContent("Runtime") {
                        VStack(alignment: .leading, spacing: 8) {
                            runtimeSelectionSummary
                            Button {
                                chooseRuntime()
                            } label: {
                                Label("Choose Wine Runtime", systemImage: "folder")
                            }
                        }
                    }
                } else {
                    Picker("Runtime", selection: Binding(
                        get: { selectedRuntimeID ?? detector.candidates.first?.id ?? "" },
                        set: { selectedRuntimeID = $0 }
                    )) {
                        ForEach(detector.candidates) { runtime in
                            Text("\(runtime.displayName) - \(runtime.locationPath)")
                                .tag(runtime.id)
                        }
                        Text("Choose manually...")
                            .tag(customRuntimeID)
                    }

                    if selectedRuntimeID == customRuntimeID {
                        LabeledContent("Runtime") {
                            HStack {
                                runtimeSelectionSummary
                                Button("Choose") {
                                    chooseRuntime()
                                }
                            }
                        }
                    }
                }

                if let customRuntimeError {
                    Text(customRuntimeError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Graphics", selection: $graphicsBackend) {
                    ForEach(GraphicsBackend.allCases) { backend in
                        Text(backend.label).tag(backend)
                    }
                }
            }

            Text("The app will create a WINEPREFIX, run Wine initialization, then keep this bottle isolated from your other Steam installs.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    guard let selectedRuntime else { return }
                    Task {
                        await store.createBottle(name: name, runtime: selectedRuntime, graphicsBackend: graphicsBackend)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            selectedRuntimeID = detector.candidates.first?.id ?? customRuntimeID
        }
    }

    @ViewBuilder
    private var runtimeSelectionSummary: some View {
        if let customRuntime {
            VStack(alignment: .leading, spacing: 2) {
                Text(customRuntime.displayName)
                    .lineLimit(1)
                Text(customRuntime.locationPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text("No Wine runtime selected")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func chooseRuntime() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Select a Wine executable or a GameNative .runtime bundle directory."
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true {
                    customRuntime = try RuntimeBundle.candidate(from: url)
                } else {
                    guard FileManager.default.isExecutableFile(atPath: url.path) else {
                        customRuntimeError = "The selected file is not executable."
                        return
                    }
                    customRuntime = RuntimeCandidate(
                        kind: .custom,
                        executablePath: url.path,
                        displayName: url.lastPathComponent
                    )
                }
                customRuntimeError = nil
                selectedRuntimeID = customRuntimeID
            } catch {
                customRuntime = nil
                customRuntimeError = error.localizedDescription
                selectedRuntimeID = customRuntimeID
            }
        }
    }
}


