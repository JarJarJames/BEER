import SwiftUI

struct AdvancedSettingsView: View {
    let bottle: Bottle
    @EnvironmentObject private var bottles: BottleStore

    var body: some View {
        let bottleID = bottle.id
        let liveBottle = bottles.bottles.first(where: { $0.id == bottleID }) ?? bottle
        let isBusy = bottles.activeBottleIDs.contains(bottleID)
        let logEntries = bottles.logs[bottleID] ?? []

        VStack(alignment: .leading, spacing: 12) {
            SettingsRow(title: "Windows version") {
                TextField("win10", text: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.windowsVersion
                            ?? liveBottle.windowsVersion
                    },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.windowsVersion = newValue }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                Spacer()
            }

            SettingsRow(title: "Notes", alignment: .top) {
                TextField("Compatibility notes", text: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.notes
                            ?? liveBottle.notes
                    },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.notes = newValue }
                    }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .frame(maxWidth: 520)
                Spacer()
            }

            EnvironmentRow(bottleID: bottleID, bottle: liveBottle)

            Divider()

            if let exe = liveBottle.gameLaunchExecutable {
                LabeledValue(key: "Launch executable", value: exe)
            }
            if let installDir = liveBottle.resolvedInstallDirectory {
                LabeledValue(key: "Install location", value: installDir.path)
            }
            LabeledValue(key: "Bottle path", value: AppPaths.prefixURL(for: liveBottle).path)
            LabeledValue(key: "Runtime path", value: liveBottle.runtimeLocationPath)

            HStack(spacing: 10) {
                Button {
                    Task { await bottles.initializeBottle(liveBottle) }
                } label: {
                    Label("Repair Prefix", systemImage: "wrench.adjustable")
                }
                .disabled(isBusy)

                Button {
                    Task { await bottles.stopBottleProcesses(liveBottle) }
                } label: {
                    Label("Stop Processes", systemImage: "stop.fill")
                }

                Button {
                    bottles.reveal(liveBottle)
                } label: {
                    Label("Reveal Bottle", systemImage: "folder")
                }

                Button {
                    bottles.copyLogToClipboard(liveBottle)
                } label: {
                    Label("Copy Log", systemImage: "doc.on.doc")
                }

                Button {
                    bottles.revealLog(liveBottle)
                } label: {
                    Label("Reveal Log", systemImage: "doc.text.magnifyingglass")
                }
            }
            .controlSize(.small)

            Text("Repair reinitializes the Wine prefix without reinstalling the game. Stop ends processes running inside this bottle.")
                .font(.caption)
                .foregroundStyle(.secondary)

            WineLogView(entries: logEntries)
            .font(.callout)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
