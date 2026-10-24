import os

/// BEER's loggers, one per area. Read them in Console.app by filtering on the
/// subsystem, or from a terminal:
///
///     log stream --predicate 'subsystem == "io.github.jarjarjames.beer"'
///
/// Interpolated values are private by default, so paths, account names and
/// tokens show as `<private>` outside a debugger. Mark a value
/// `privacy: .public` only when it can't identify the user.
enum Log {
    static let subsystem = "io.github.jarjarjames.beer"

    static let cloudSync = Logger(subsystem: subsystem, category: "cloud-sync")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let install = Logger(subsystem: subsystem, category: "install")
    static let session = Logger(subsystem: subsystem, category: "play-session")
    static let achievements = Logger(subsystem: subsystem, category: "achievements")
}
