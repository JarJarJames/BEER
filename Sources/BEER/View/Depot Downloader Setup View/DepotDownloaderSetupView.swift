import SwiftUI

struct DepotDownloaderSetupView: View {
    @EnvironmentObject private var depot: DepotDownloaderInstaller

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Welcome to BEER")
                .font(.largeTitle.bold())
            Text("First, we'll install DepotDownloader — an open-source, native macOS Steam downloader. No Wine, no Steam client UI, and you sign in by scanning a QR code with the Steam Mobile App instead of typing a password.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 600)
                .fixedSize(horizontal: false, vertical: true)

            if depot.isInstalling {
                ProgressView().controlSize(.large)
            }

            Text(depot.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                Task { await depot.install() }
            } label: {
                Label(depot.isInstalled ? "Reinstall DepotDownloader" : "Install DepotDownloader", systemImage: "arrow.down.circle.fill")
                    .font(.title3)
                    .frame(minWidth: 280, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(depot.isInstalling)

            if let error = depot.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Onboarding step 2: sign in


