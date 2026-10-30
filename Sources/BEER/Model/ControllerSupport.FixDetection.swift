import Foundation

extension ControllerSupport {
    /// What the controller fix found among the connected pads.
    enum FixDetection: Equatable, Sendable {
        /// A pad whose layout the fix was measured on.
        case supported(FixProfile, Gamepad)
        /// Pads are connected, but none has a measured layout, so the fix
        /// stays out of the way.
        case unsupported([Gamepad])
        case noGamepad
    }
}
