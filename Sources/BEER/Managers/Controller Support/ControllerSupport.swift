import Foundation
import IOKit
import IOKit.hid

/// Makes game controllers visible to Wine.
///
/// macOS hands every pad to Wine through IOHID, which Wine's bus driver
/// classifies as a "hidraw" device. `winebus` refuses to create hidraw gamepads
/// unless their `vid:pid` appears in its `EnableHidraw` value — it enumerates
/// them, logs `ignoring hidraw device <vid>:<pid>`, and drops them, so XInput
/// reports zero controllers and games see nothing.
///
/// Wine's built-in exceptions cover pads it recognises by ID, which leaves out
/// anything synthesised: notably the virtual Xbox 360 pad (`045e:028e`) Steam
/// publishes for a Steam Controller, and the virtual pads other remapping tools
/// create. Rather than chase an ID list, we whitelist whatever the Mac itself
/// currently reports as a gamepad.
enum ControllerSupport {
    /// Every gamepad/joystick macOS currently exposes, as lowercase `vid:pid`
    /// — the form `winebus` parses out of `EnableHidraw`.
    static func connectedDeviceIdentifiers() -> [String] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Generic Desktop gamepad / joystick / multi-axis — the same usages
        // Wine's IOHID backend accepts as "a joystick or gamepad".
        let matching = [kHIDUsage_GD_GamePad, kHIDUsage_GD_Joystick, kHIDUsage_GD_MultiAxisController]
            .map { [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0] }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        // Enumeration only — we never open the devices, so this needs no Input
        // Monitoring permission and never competes with the app holding the pad.
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }

        var identifiers: Set<String> = []
        for device in devices {
            guard let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
                  let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
                  vendor != 0
            else { continue }
            identifiers.insert(String(format: "%04x:%04x", vendor, product))
        }
        return identifiers.sorted()
    }
}
