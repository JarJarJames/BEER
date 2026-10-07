import Foundation

/// Collapses away once we know the account owns no DLC for this game.
enum DLCRowState {
    case installed(owned: Int, installed: Int)
    case loading
    case failed
    case unchecked
}
