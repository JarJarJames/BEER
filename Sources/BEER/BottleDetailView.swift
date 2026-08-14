import AppKit
import SwiftUI

struct BottleDetailView: View {
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector
    @State var bottle: Bottle
    @State private var selectedRuntimeID: RuntimeCandidate.ID?
    @State private var runtimeSelectionError: String?

    private var isBusy: Bool {
        store.activeBottleIDs.contains(bottle.id)
    }

    private var logEntries: [BottleLogEntry] {
        store.logs[bottle.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    configuration
                    actions
                    logs
                }
                .padding(22)
            }
        }
        .onChange(of: bottle) { _, newValue in
            Task { await store.update(newValue) }
        }
        .onChange(of: store.selectedBottle?.id) { _, _ in
            if let selected = store.selectedBottle {
                bottle = selected
                selectedRuntimeID = selected.runtimeLocationPath
                runtimeSelectionError = nil
            }
        }
        .onAppear {
            selectedRuntimeID = bottle.runtimeLocationPath
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Bottle name", text: $bottle.name)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                Text(AppPaths.prefixURL(for: bottle).path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Button(role: .destructive) {
                Task { await store.delete(bottle) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isBusy)
        }
        .padding(22)
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Runtime")
                        .foregroundStyle(.secondary)
                    RuntimeMenuView(
                        bottle: $bottle,
                        selectedRuntimeID: $selectedRuntimeID,
                        runtimeSelectionError: $runtimeSelectionError,
                        isBusy: isBusy
                    )
                }
                GridRow {
                    Text("Graphics")
                        .foregroundStyle(.secondary)
                    Picker("Graphics", selection: $bottle.graphicsBackend) {
                        ForEach(GraphicsBackend.allCases) { backend in
                            Text(backend.label).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                GridRow {
                    Text("Windows")
                        .foregroundStyle(.secondary)
                    TextField("Windows version", text: $bottle.windowsVersion)
                        .frame(width: 220)
                }
                GridRow {
                    Text("Notes")
                        .foregroundStyle(.secondary)
                    TextField("Compatibility notes", text: $bottle.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 10) {
                Button {
                    Task { await store.initializeBottle(bottle) }
                } label: {
                    Label("Repair", systemImage: "wrench.adjustable")
                }
                .disabled(isBusy)

                Button {
                    Task { await store.stopBottleProcesses(bottle) }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }

                Button {
                    store.reveal(bottle)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
            }

            Text("Repair reinitializes the Wine prefix without reinstalling the game. Stop ends processes running inside this bottle.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log")
                .font(.headline)

            HStack {
                Button {
                    store.copyLogToClipboard(bottle)
                } label: {
                    Label("Copy Log", systemImage: "doc.on.doc")
                }

                Button {
                    store.revealLog(bottle)
                } label: {
                    Label("Reveal Wine Log", systemImage: "doc.text.magnifyingglass")
                }

                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(logEntries) { entry in
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(entry.isError ? .red : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .frame(minHeight: 190)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if logEntries.isEmpty {
                        Text("No log output yet.")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: logEntries.count) { _, _ in
                    if let last = logEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

}
