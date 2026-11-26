import Foundation

extension GameDetailViewModel {
    /// A shortcut opened this page: start the game unless it isn't installed
    /// (the page then shows Install) or is already running.
    func launchFromShortcut() {
        guard let bottle = installedBottle, bottle.gameLaunchExecutable != nil,
              !bottles.activeBottleIDs.contains(bottle.id) else { return }
        launch(bottle)
    }

    func createShortcut(_ kind: GameShortcutKind) {
        Task { [self] in
            do {
                try await shortcuts.create(kind, for: game)
                cloudSyncIsError = false
                cloudSyncMessage = GameShortcutStrings.created(kind)
            } catch {
                cloudSyncIsError = true
                cloudSyncMessage = GameShortcutStrings.failed(
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }

    /// The icon sheet saved a new pick: the game's shortcuts get it too.
    func shortcutIconSaved(_ choice: ShortcutIconChoice) {
        sheet = nil
        library.setShortcutIcon(choice, appID: appID)
        Task { [self] in
            do {
                try await shortcuts.updateIcons(for: game)
            } catch {
                cloudSyncIsError = true
                cloudSyncMessage = GameShortcutStrings.failed(
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }

    /// The shortcuts ticked in the install sheet, made once the game is in.
    /// A failure goes to the download log; the install itself succeeded.
    func createShortcutsChosenAtInstall(appID: Int) async {
        for kind in GameShortcutPreferences.kindsToCreateOnInstall() {
            do {
                try await shortcuts.create(kind, for: game)
            } catch {
                downloads.append(appID: appID, log: GameShortcutStrings.failed(
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ))
            }
        }
    }
}
