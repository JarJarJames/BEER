import Foundation

extension ControllerSupport {
    /// A pad the controller fix has been measured against.
    ///
    /// `dpad_helper` decodes fixed bit offsets, which are only right for the
    /// exact report layout they were measured on. So a pad matches by its
    /// descriptor's fingerprint, not just its vendor/product: the same IDs with
    /// a different layout is a different pad as far as the fix is concerned.
    struct FixProfile: Equatable, Sendable {
        let name: String
        let vendorID: Int
        let productID: Int
        /// SHA-256 of the HID report descriptor, lowercase hex.
        let descriptorSHA256: String

        func matches(_ pad: Gamepad) -> Bool {
            pad.vendorID == vendorID
                && pad.productID == productID
                && SHA256Digest.hexDigest(pad.reportDescriptor) == descriptorSHA256
        }
    }
}
