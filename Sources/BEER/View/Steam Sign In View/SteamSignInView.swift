import SwiftUI

struct SteamSignInView: View {
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var auth: SteamAuthStore

    @StateObject private var qr = SteamQRAuthViewModel()

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

            QRCodeView(challengeURL: qr.session?.challengeURL, hasError: qr.error != nil)
                .frame(width: 260, height: 260)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if library.isFetchingLibrary {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Fetching your library…").font(.callout).foregroundStyle(.secondary)
                }
            } else if let error = qr.error {
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
        .onDisappear { qr.cancel() }
    }

    private func startAuthIfNeeded() {
        library.lastError = nil
        qr.start(auth: auth, fallbackError: "Sign-in failed.", onApproved: signIn)
    }

    private func restart() {
        qr.restart(auth: auth, fallbackError: "Sign-in failed.", onApproved: signIn)
    }

    // ContentView re-routes to the library grid once
    // library.account.isLoggedIn flips true.
    private func signIn() async {
        await library.signInWithQR(auth: auth)
    }
}
