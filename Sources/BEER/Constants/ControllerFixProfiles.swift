import Foundation

/// Pads the controller fix is proven on. Add one only after measuring its
/// reports against real presses; see `Tools/ControllerFix/README.md`.
enum ControllerFixProfiles {
    /// The virtual Xbox 360 pad Steam for macOS publishes for a Steam
    /// Controller: D-pad as buttons 12-15, no hat switch, menu buttons
    /// declared out of order.
    static let steamVirtualGamepad = ControllerSupport.FixProfile(
        name: "Steam Controller",
        vendorID: 0x045e,
        productID: 0x028e,
        descriptorSHA256: "086699843817c3d3554b4de8d239d809407b328eafa4a82aae93284f669524a7"
    )

    static let all = [steamVirtualGamepad]
}
