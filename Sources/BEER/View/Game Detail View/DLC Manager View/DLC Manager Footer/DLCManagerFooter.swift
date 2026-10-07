import SwiftUI

struct DLCManagerFooter: View {
    let pending: [CloudSyncClient.DLCInfo]
    @ObservedObject var model: DLCManagerViewModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = model.message {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(message.isError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if !pending.isEmpty {
                    Button(model.isInstallingAll ? "Installing…" : "Install all (\(pending.count))") {
                        model.installAll(pending)
                    }
                    .disabled(model.isBusy)
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
