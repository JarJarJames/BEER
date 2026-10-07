import SwiftUI

/// The Steam sign-in QR: the code once Steam has issued a challenge, a spinner
/// while waiting, or a warning if the attempt failed.
struct QRCodeView: View {
    let challengeURL: String?
    let hasError: Bool

    var body: some View {
        if let challengeURL, let cgImage = QRCodeGenerator.image(from: challengeURL) {
            Image(decorative: cgImage, scale: 1.0)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if hasError {
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
}
