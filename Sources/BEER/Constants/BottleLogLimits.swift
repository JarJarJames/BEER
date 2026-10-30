import Foundation

/// How much of a bottle's log BEER keeps in memory. `beer.log` on disk always
/// gets every line; this only bounds what the app holds and shows.
enum BottleLogLimits {
    /// A Wine debug channel left on (`WINEDEBUG=+cursor`) can print hundreds of
    /// thousands of lines in one session. Uncapped, every append copied the
    /// whole list on the main thread and BEER froze working through it.
    static let inMemoryEntries = 2000
}
