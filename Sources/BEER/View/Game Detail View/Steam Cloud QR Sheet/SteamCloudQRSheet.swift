import SwiftUI

// Sheet that runs SteamAuthStore.runQRAuth — show a real QR rendered from
// the challenge URL (we don't have to parse ASCII art here because we
// drive auth ourselves and own the URL string). When the user approves on
// their Steam Mobile App, the poll loop inside the auth store completes
// and the sheet dismisses.

struct SteamCloudQRSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: SteamAuthStore

    let onConnected: () -> Void

    @StateObject private var qr = SteamQRAuthViewModel()

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "icloud.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                Text("Connect Steam Cloud")
                    .font(.title2.bold())
                Text("Scan the code with the Steam Mobile App and tap **Approve**. We use the resulting token only for Cloud read/write — your password is never sent to this app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
            }

            QRCodeView(challengeURL: qr.session?.challengeURL, hasError: qr.error != nil)
                .frame(width: 280, height: 280)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if let error = qr.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: 380)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for approval…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 380)
            }

            HStack {
                Spacer()
                Button(role: .destructive) {
                    qr.cancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                }
            }
            .frame(maxWidth: 380)
        }
        .padding(28)
        .frame(width: 440)
        .interactiveDismissDisabled(true)
        .onAppear { startAuthIfNeeded() }
        .onDisappear { qr.cancel() }
    }

    private func startAuthIfNeeded() {
        qr.start(auth: auth, fallbackError: "Steam sign-in failed.") {
            // Completed — caller wants to know, then dismiss.
            onConnected()
            dismiss()
        }
    }
}
