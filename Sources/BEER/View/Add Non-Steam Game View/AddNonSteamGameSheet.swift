import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AddNonSteamGameSheet: View {
    @StateObject private var model: AddNonSteamGameViewModel
    @Environment(\.dismiss) private var dismiss

    init(bottles: BottleStore, library: SteamLibraryStore, detector: ToolchainDetector) {
        _model = StateObject(wrappedValue: AddNonSteamGameViewModel(bottles: bottles, library: library, detector: detector))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Non-Steam Game").font(.title2.bold())
            Text("Bring a game you already have into BEER. It gets its own GPTK bottle and settings, like a Steam game.")
                .font(.callout)
                .foregroundStyle(.secondary)

            row("Game folder") {
                HStack {
                    Text(model.folder?.path ?? "None chosen")
                        .foregroundStyle(model.folder == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…", action: chooseFolder)
                }
            }

            row("Name") {
                TextField("Game name", text: $model.name)
            }

            row("Launch executable") {
                HStack {
                    if model.isScanning {
                        ProgressView().controlSize(.small)
                        Text("Looking for executables…").foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        Picker("", selection: $model.selectedExecutable) {
                            if model.selectedExecutable == nil { Text("None").tag(URL?.none) }
                            ForEach(model.executables, id: \.self) { exe in
                                Text(model.relativePath(of: exe)).tag(URL?.some(exe))
                            }
                        }
                        .labelsHidden()
                        .disabled(model.folder == nil)
                        Button("Browse…", action: chooseExecutable)
                            .disabled(model.folder == nil)
                    }
                }
            }

            row("Cover image (optional)") {
                HStack {
                    Text(model.imageURL?.lastPathComponent ?? "None")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if model.imageURL != nil {
                        Button("Clear") { model.setImage(nil) }
                    }
                    Button("Choose…", action: chooseImage)
                }
            }

            row("Game files") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("", selection: $model.transferMode) {
                        Text("Move into BEER").tag(GameFolderTransfer.Mode.move)
                        Text("Copy into BEER").tag(GameFolderTransfer.Mode.copy)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(model.transferMode == .move
                         ? "The folder is moved, so there's still one copy. Removing the game from BEER later deletes it."
                         : "The original stays where it is. Needs room for a second copy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.hasRuntime {
                Text("No Wine runtime available. Open Runtime Manager in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                if model.isWorking {
                    ProgressView().controlSize(.small)
                    Text("Setting up the game…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isWorking)
                Button("Add Game") {
                    Task { if await model.add() { dismiss() } }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canAdd)
            }
        }
        .padding(24)
        .frame(width: 560)
        .interactiveDismissDisabled(model.isWorking)
        .alert("Couldn't add game", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that contains the game."
        if panel.runModal() == .OK, let url = panel.url { model.setFolder(url) }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.folder
        if let exe = UTType(filenameExtension: "exe") { panel.allowedContentTypes = [exe] }
        panel.message = "Choose the game's executable (inside the game folder)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addExecutable(url)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url { model.setImage(url) }
    }
}
