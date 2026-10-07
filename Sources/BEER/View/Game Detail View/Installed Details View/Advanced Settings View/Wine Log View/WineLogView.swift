import SwiftUI

struct WineLogView: View {
    let entries: [BottleLogEntry]

    var body: some View {
        DisclosureGroup("Wine log") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(entries) { entry in
                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(entry.isError ? .red : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .frame(minHeight: 120, maxHeight: 240)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if entries.isEmpty {
                    Text("No log output yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        }
    }
}
