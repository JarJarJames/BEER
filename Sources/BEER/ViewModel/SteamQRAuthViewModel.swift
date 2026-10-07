import Foundation

/// Drives one QR sign-in attempt for the sign-in screen and the Steam Cloud
/// sheet: holds the challenge once Steam issues it, any failure, and the task
/// polling for approval on the phone.
@MainActor
final class SteamQRAuthViewModel: ObservableObject {
    @Published private(set) var session: SteamAuthStore.QRSession?
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?

    /// Starts the attempt unless one is already running. `onApproved` runs once
    /// the user approves on their phone.
    func start(
        auth: SteamAuthStore,
        fallbackError: String,
        onApproved: @escaping @MainActor () async -> Void
    ) {
        guard task == nil else { return }
        error = nil
        task = Task { [self] in
            do {
                try await auth.runQRAuth { qr in self.session = qr }
                await onApproved()
            } catch is CancellationError {
                // view went away, or the user cancelled
            } catch let err as SteamAuthError {
                error = err.errorDescription ?? fallbackError
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func restart(
        auth: SteamAuthStore,
        fallbackError: String,
        onApproved: @escaping @MainActor () async -> Void
    ) {
        task?.cancel()
        task = nil
        session = nil
        error = nil
        start(auth: auth, fallbackError: fallbackError, onApproved: onApproved)
    }
}
