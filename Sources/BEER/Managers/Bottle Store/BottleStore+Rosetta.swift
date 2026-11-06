import Foundation

extension BottleStore {
    /// Whether Wine can run. When Rosetta is missing, asks to install it
    /// rather than letting Wine fail with "Bad CPU type in executable".
    func requireRosetta() -> Bool {
        if rosettaInstalled() { return true }
        isShowingRosettaPrompt = true
        return false
    }

    func installRosetta() async {
        do {
            _ = try await RosettaInstaller.install()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
