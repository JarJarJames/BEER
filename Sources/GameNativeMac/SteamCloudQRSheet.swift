import CoreImage
import CoreImage.CIFilterBuiltins
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

    @State private var session: SteamAuthStore.QRSession?
    @State private var error: String?
    @State private var task: Task<Void, Never>?

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

            qrView
                .frame(width: 280, height: 280)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if let error {
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
                    task?.cancel()
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
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private var qrView: some View {
        if let urlString = session?.challengeURL,
           let cgImage = generateQR(from: urlString) {
            Image(decorative: cgImage, scale: 1.0)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if error != nil {
            VStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Couldn't get a QR from Steam.")
                    .foregroundStyle(.black)
            }
        } else {
            ProgressView()
        }
    }

    private func startAuthIfNeeded() {
        guard task == nil else { return }
        task = Task {
            do {
                try await auth.runQRAuth { qr in
                    self.session = qr
                }
                // Completed — caller wants to know, then dismiss.
                onConnected()
                dismiss()
            } catch is CancellationError {
                // user clicked Cancel; sheet already dismissed
            } catch let err as SteamAuthError {
                self.error = err.errorDescription ?? String(describing: err)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func generateQR(from string: String) -> CGImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        // Upscale so the image isn't a tiny pixelated mess when scaled.
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
