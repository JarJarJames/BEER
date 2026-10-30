import Foundation

/// The automatic controller fix, applied per launch by
/// `BottleStore.prepareControllerFix`.
///
/// Some pads reach Wine through a virtual HID gamepad whose report Wine's
/// `winexinput.sys` mangles: it reads a D-pad only from a hat switch and drops
/// button usages above 10, so a pad reporting its D-pad as buttons 12-15 loses
/// it inside the driver. The fix is two halves — a macOS helper that reads the
/// pad where the data still exists, and a `hid.dll` shim in the bottle that
/// feeds it back in. `Tools/ControllerFix/README.md` has the full story.
///
/// It applies itself only to a pad whose report layout it was measured on
/// (`ControllerFixProfiles`), and inside the bottle the shim touches only that
/// pad, so any other controller is passed through unchanged.
extension ControllerSupport {
    /// A shipped .app bundles both halves; a `swift run` build uses what
    /// `Tools/ControllerFix/build.sh` installed into Application Support.
    static var helperURL: URL {
        let bundled = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .deletingLastPathComponent()
            .appendingPathComponent("dpad_helper")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : AppPaths.controllerFixHelperURL
    }

    static var shimURL: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("hid.dll"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return AppPaths.controllerFixShimURL
    }

    /// Both artifacts have to be present; the shim forwards most of its
    /// exports to Wine's own hid.dll and aborts on the first call without it.
    static var fixIsInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: helperURL.path)
            && FileManager.default.fileExists(atPath: shimURL.path)
    }

    /// The first connected pad with a measured layout, if any.
    static func detectFix(
        among pads: [Gamepad],
        profiles: [FixProfile] = ControllerFixProfiles.all
    ) -> FixDetection {
        for pad in pads {
            if let profile = profiles.first(where: { $0.matches(pad) }) {
                return .supported(profile, pad)
            }
        }
        return pads.isEmpty ? .noGamepad : .unsupported(pads)
    }

    /// The shim is an x86_64 PE; a 32-bit game can't load it.
    static func isX86_64Executable(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4096) else { return false }
        return peMachine(of: header) == 0x8664
    }

    /// The COFF machine field of a PE image, or nil if `header` isn't one.
    static func peMachine(of header: Data) -> UInt16? {
        let bytes = [UInt8](header)
        guard bytes.count >= 0x40, bytes[0] == 0x4d, bytes[1] == 0x5a else { return nil }
        let pe = (0..<4).reduce(0) { $0 | Int(bytes[0x3c + $1]) << (8 * $1) }
        guard pe + 6 <= bytes.count, Array(bytes[pe..<pe + 4]) == [0x50, 0x45, 0, 0] else { return nil }
        return UInt16(bytes[pe + 4]) | UInt16(bytes[pe + 5]) << 8
    }

    /// Install `hid.dll` next to the game's executable, alongside a copy of the
    /// runtime's own hid.dll renamed `hid_orig.dll` for the shim to forward to.
    static func installShim(forExecutable executable: String, runtimeHid: URL?) throws {
        guard fixIsInstalled else { throw FixError.artifactsMissing }
        guard let runtimeHid, FileManager.default.fileExists(atPath: runtimeHid.path) else {
            throw FixError.runtimeHidMissing
        }

        let directory = URL(fileURLWithPath: executable).deletingLastPathComponent()
        try copy(shimURL, to: directory.appendingPathComponent("hid.dll"))
        try copy(runtimeHid, to: directory.appendingPathComponent("hid_orig.dll"))
    }

    /// Take the shim back out when this launch doesn't use it. `hid_orig.dll`
    /// is what marks the pair as ours; a game's own `hid.dll` is left alone.
    static func removeShim(forExecutable executable: String) {
        let directory = URL(fileURLWithPath: executable).deletingLastPathComponent()
        let original = directory.appendingPathComponent("hid_orig.dll")
        guard FileManager.default.fileExists(atPath: original.path) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("hid.dll"))
        try? FileManager.default.removeItem(at: original)
    }

    /// Start the macOS-side reader. It attaches only to a device matching the
    /// profile's descriptor fingerprint, follows it across reconnects, and the
    /// shim picks its output up from `drive_c\beer_dpad.bin`.
    static func startHelper(profile: FixProfile, prefix: URL) -> Process? {
        guard fixIsInstalled else { return nil }
        CloudSyncClient.clearQuarantineIfNeeded(helperURL)

        let process = Process()
        process.executableURL = helperURL
        process.arguments = [
            String(format: "0x%04x", profile.vendorID),
            String(format: "0x%04x", profile.productID),
            profile.descriptorSHA256,
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
