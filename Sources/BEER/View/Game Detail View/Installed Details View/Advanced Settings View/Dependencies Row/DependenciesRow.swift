import SwiftUI

/// One-click Microsoft runtimes for this bottle — BEER's take on Whisky's
/// winetricks menu, limited to the prerequisites games actually ask for.
struct DependenciesRow: View {
    let bottle: Bottle
    @EnvironmentObject private var bottles: BottleStore
    @EnvironmentObject private var installer: WindowsDependencyInstaller

    var body: some View {
        let installed = installer.installed[bottle.id] ?? []
        let isBottleBusy = bottles.activeBottleIDs.contains(bottle.id)

        VStack(alignment: .leading, spacing: DependenciesRowLayout.spacing) {
            SettingsRow(title: WindowsDependencyStrings.rowTitle, alignment: .top) {
                VStack(alignment: .leading, spacing: DependenciesRowLayout.spacing) {
                    ForEach(WindowsDependency.allCases) { dependency in
                        dependencyLine(dependency, isInstalled: installed.contains(dependency), isBottleBusy: isBottleBusy)
                    }

                    if installer.busy?.bottleID == bottle.id, let status = installer.statusMessage[bottle.id] {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = installer.lastError[bottle.id] {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }

            Text(WindowsDependencyStrings.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: bottle.id) {
            installer.refresh(bottle)
        }
    }

    private func dependencyLine(_ dependency: WindowsDependency, isInstalled: Bool, isBottleBusy: Bool) -> some View {
        HStack(spacing: DependenciesRowLayout.spacing) {
            VStack(alignment: .leading, spacing: DependenciesRowLayout.titleSpacing) {
                Text(dependency.title)
                Text(dependency.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: DependenciesRowLayout.titleWidth, alignment: .leading)

            if installer.busy == WindowsDependencyInstaller.Job(bottleID: bottle.id, dependency: dependency) {
                ProgressView().controlSize(.small)
            } else {
                if isInstalled {
                    Label(WindowsDependencyStrings.installed, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button(isInstalled ? WindowsDependencyStrings.reinstall : WindowsDependencyStrings.install) {
                    Task { await installer.install(dependency, into: bottle, using: bottles) }
                }
                .controlSize(.small)
                .disabled(installer.busy != nil || isBottleBusy)
            }
        }
    }
}
