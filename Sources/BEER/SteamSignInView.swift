import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SteamSignInView: View {
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var auth: SteamAuthStore

    @State private var session: SteamAuthStore.QRSession?
    @State private var error: String?
    @State private var authTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "qrcode")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Sign in to Steam")
                .font(.largeTitle.bold())
            Text("Scan this code with the Steam Mobile App and tap **Approve**. This signs you in to your library and Cloud saves in one step — your password is never typed into this app.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560)
                .fixedSize(horizontal: false, vertical: true)

            qrView
                .frame(width: 260, height: 260)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if library.isFetchingLibrary {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Fetching your library…").font(.callout).foregroundStyle(.secondary)
                }
            } else if let error {
                VStack(spacing: 10) {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                    Button("Try again") { restart() }
                        .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for approval in the Steam Mobile App…")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "iphone")
                Text("Open Steam on your phone → tap the QR-scan icon (top-left) → scan.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startAuthIfNeeded() }
        .onDisappear { authTask?.cancel() }
    }

    @ViewBuilder
    private var qrView: some View {
        if let urlString = session?.challengeURL, let cgImage = Self.generateQR(from: urlString) {
            Image(decorative: cgImage, scale: 1.0)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if error != nil {
            VStack {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text("Couldn't get a QR from Steam.").foregroundStyle(.black)
            }
        } else {
            ProgressView()
        }
    }

    private func startAuthIfNeeded() {
        guard authTask == nil else { return }
        error = nil
        library.lastError = nil
        authTask = Task {
            do {
                try await auth.runQRAuth { qr in self.session = qr }
                await library.signInWithQR(auth: auth)
                // ContentView re-routes to the library grid once
                // library.account.isLoggedIn flips true.
            } catch is CancellationError {
                // view went away
            } catch let err as SteamAuthError {
                self.error = err.errorDescription ?? "Sign-in failed."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func restart() {
        authTask?.cancel()
        authTask = nil
        session = nil
        error = nil
        startAuthIfNeeded()
    }

    private static func generateQR(from string: String) -> CGImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

// MARK: - Library grid


