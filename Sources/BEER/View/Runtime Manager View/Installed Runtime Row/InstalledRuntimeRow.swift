import SwiftUI

struct InstalledRuntimeRow: View {
    let runtime: RuntimeCandidate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: runtime.kind == .gamePortingToolkit ? "hammer.fill" : "wineglass.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(runtime.displayName)
                    .font(.callout.weight(.medium))
                Text("\(runtime.kind.label) · \(runtime.locationPath)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
        .padding(.vertical, 8)
    }
}
