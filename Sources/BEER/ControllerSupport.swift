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

/// The opt-in per-game controller fix (`Bottle.controllerFix`).
///
/// Some pads reach Wine through a virtual HID gamepad whose report Wine's
/// `winexinput.sys` mangles: it reads a D-pad only from a hat switch and drops
/// button usages above 10, so a pad reporting its D-pad as buttons 12-15 loses
/// it inside the driver. The fix is two halves — a macOS helper that reads the
/// pad where the data still exists, and a `hid.dll` shim in the bottle that
/// feeds it back in. `Tools/ControllerFix/README.md` has the full story.
///
/// Off by default, because the shim rewrites what the game reads from the HID
/// device and that is only correct for pads Wine actually mishandles.
extension ControllerSupport {
    enum FixError: LocalizedError {
        case artifactsMissing
        case runtimeHidMissing

        var errorDescription: String? {
            switch self {
            case .artifactsMissing:
                return "Controller fix is not installed. Run Tools/ControllerFix/build.sh."
            case .runtimeHidMissing:
                return "This bottle's Wine runtime has no hid.dll to forward to."
            }
        }
    }

    /// Both artifacts have to be present; the shim forwards all but two of its
    /// exports to Wine's own hid.dll and aborts on the first call without it.
    static var fixIsInstalled: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: AppPaths.controllerFixHelperURL.path)
            && fm.fileExists(atPath: AppPaths.controllerFixShimURL.path)
    }

    /// Install `hid.dll` next to the game's executable, alongside a copy of the
    /// runtime's own hid.dll renamed `hid_orig.dll` for the shim to forward to.
    static func installShim(forExecutable executable: String, runtimeHid: URL?) throws {
        guard fixIsInstalled else { throw FixError.artifactsMissing }
        guard let runtimeHid, FileManager.default.fileExists(atPath: runtimeHid.path) else {
            throw FixError.runtimeHidMissing
        }

        let directory = URL(fileURLWithPath: executable).deletingLastPathComponent()
        try copy(AppPaths.controllerFixShimURL, to: directory.appendingPathComponent("hid.dll"))
        try copy(runtimeHid, to: directory.appendingPathComponent("hid_orig.dll"))
    }

    /// Start the macOS-side reader for the pad. The shim picks its output up
    /// from `drive_c\beer_dpad.bin`, so nothing needs to be passed to the game.
    static func startHelper(prefix: URL, device: String) -> Process? {
        guard fixIsInstalled else { return nil }

        let process = Process()
        process.executableURL = AppPaths.controllerFixHelperURL
        process.arguments = [
            "0x" + String(device.prefix(4)),
            "0x" + String(device.suffix(4)),
            prefix.appendingPathComponent("drive_c/beer_dpad.bin").path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            return process
        } catch {
            return nil
        }
    }

    private static func copy(_ source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
