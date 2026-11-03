import SwiftUI

/// The places a game can go, Steam-style: one row per place with its free
/// space. The chosen row is filled; a place that can't be used is greyed out
/// with the reason. Used by the install, move and add-game sheets.
struct InstallTargetList: View {
    let options: [InstallTargetOption]
    @Binding var selection: InstallTarget?
    /// Turns the chosen row red: what's going there won't fit.
    var selectionDoesNotFit: Bool = false

    var body: some View {
        VStack(spacing: InstallTargetListLayout.rowSpacing) {
            ForEach(options) { option in
                Button { selection = option.target } label: { row(option) }
                    .buttonStyle(.plain)
                    .disabled(!option.isEnabled)
            }
        }
    }

    private func row(_ option: InstallTargetOption) -> some View {
        // By ID: a drive's free space changes while the sheet is open.
        let isSelected = option.id == selection?.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: option.target.volume == nil ? "internaldrive" : "externaldrive")
                Text(option.target.name)
                    .font(.title3)
                Spacer()
                Text(option.availableBytes.map(InstallDriveStrings.free) ?? InstallDriveStrings.freeUnknown)
                    .font(.headline)
            }
            if let reason = option.disabledReason {
                Text(reason)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(InstallTargetListLayout.rowPadding)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(fill(isSelected: isSelected), in: RoundedRectangle(cornerRadius: InstallTargetListLayout.cornerRadius))
        .opacity(option.isEnabled ? 1 : InstallTargetListLayout.disabledOpacity)
        .contentShape(Rectangle())
    }

    private func fill(isSelected: Bool) -> Color {
        guard isSelected else { return Color.secondary.opacity(InstallTargetListLayout.unselectedFill) }
        return selectionDoesNotFit ? .red : .accentColor
    }
}
