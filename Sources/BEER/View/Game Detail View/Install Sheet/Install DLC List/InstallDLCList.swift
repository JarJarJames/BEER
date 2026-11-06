import SwiftUI

/// The install sheet's fold-down list of DLC that download with the game, each
/// with a checkbox, like the DLC tab of Steam's install dialog.
struct InstallDLCList: View {
    let dlc: [InstallableDLC]
    let skipped: Set<Int>
    let onSet: (_ appID: Int, _ included: Bool) -> Void
    @State private var isExpanded = false

    var body: some View {
        let included = dlc.filter { !skipped.contains($0.appID) }.count

        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(dlc) { item in
                        HStack {
                            Toggle(item.name, isOn: Binding(
                                get: { !skipped.contains(item.appID) },
                                set: { onSet(item.appID, $0) }
                            ))
                            .toggleStyle(.checkbox)
                            Spacer()
                            Text(item.bytes.map(InstallSheetStrings.size) ?? InstallSheetStrings.unknownSize)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.top, 6)
            }
            // Short lists take only their own height; long ones scroll.
            .frame(maxHeight: InstallSheetLayout.dlcListMaxHeight)
            .fixedSize(horizontal: false, vertical: dlc.count <= InstallSheetLayout.dlcRowsWithoutScrolling)
        } label: {
            Text(InstallSheetStrings.dlc(included: included, of: dlc.count))
                .font(.headline)
        }
    }
}
