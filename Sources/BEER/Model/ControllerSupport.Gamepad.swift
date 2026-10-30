import Foundation

extension ControllerSupport {
    /// A gamepad macOS currently exposes, read from IOHID without opening it.
    struct Gamepad: Equatable, Sendable {
        let vendorID: Int
        let productID: Int
        let name: String
        /// The device's HID report descriptor: the layout its reports follow.
        let reportDescriptor: Data

        /// Lowercase `vid:pid`, the form `winebus` parses out of `EnableHidraw`.
        var identifier: String {
            String(format: "%04x:%04x", vendorID, productID)
        }
    }
}
