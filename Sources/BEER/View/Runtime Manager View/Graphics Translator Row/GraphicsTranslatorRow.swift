import SwiftUI

struct GraphicsTranslatorRow: View {
    let translator: GraphicsTranslator
    @EnvironmentObject private var translators: GraphicsTranslatorInstaller

    var body: some View {
        let downloaded = translators.installed.contains(translator)
        let busy = translators.busy == translator
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(translator.displayName).font(.callout.weight(.medium))
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else if downloaded {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Button {
                    Task { try? await translators.ensureDownloaded(translator) }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .disabled(translators.busy != nil)
            }
        }
        .padding(.vertical, 8)
    }
}
