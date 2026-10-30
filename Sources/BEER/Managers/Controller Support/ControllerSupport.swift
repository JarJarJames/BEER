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
        Set(connectedGamepads().map(\.identifier)).sorted()
    }

    /// Whether this launch reads pads through Wine's SDL bus instead of its
    /// raw HID bus, because a pad the raw bus can't give XInput is connected.
    /// See `SDLRoutedGamepads`.
    static func usesSDLRoute(_ identifiers: [String]) -> Bool {
        identifiers.contains(where: SDLRoutedGamepads.identifiers.contains)
    }

    /// SDL skips Steam's virtual pads unless the app runs under Steam, so on
    /// the SDL route a Steam Controller would vanish without this.
    static let allowSteamVirtualGamepadVariable = "SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD"

    /// The `winebus` settings for a launch, as a file for `reg import`. Both
    /// values are written every time so a previous launch's route never lingers.
    static func winebusRegistry(identifiers: [String], sdlRoute: Bool) -> String {
        [
            "REGEDIT4",
            "",
            #"[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\winebus]"#,
            #""EnableHidraw"="\#(identifiers.joined(separator: ","))""#,
            #""DisableHidraw"=dword:0000000\#(sdlRoute ? 1 : 0)"#,
            ""
        ].joined(separator: "\r\n")
    }

    /// Every gamepad/joystick macOS currently exposes.
    static func connectedGamepads() -> [Gamepad] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Generic Desktop gamepad / joystick / multi-axis — the same usages
        // Wine's IOHID backend accepts as "a joystick or gamepad".
        let matching = [kHIDUsage_GD_GamePad, kHIDUsage_GD_Joystick, kHIDUsage_GD_MultiAxisController]
            .map { [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0] }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        // Enumeration only — we never open the devices, so this needs no Input
        // Monitoring permission and never competes with the app holding the pad.
        // The report descriptor is a registry property, readable without opening.
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }

        return devices.compactMap { device in
            guard let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
                  let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
                  vendor != 0
            else { return nil }
            return Gamepad(
                vendorID: vendor,
                productID: product,
                name: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Controller",
                reportDescriptor: IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data ?? Data()
            )
        }
    }
}
