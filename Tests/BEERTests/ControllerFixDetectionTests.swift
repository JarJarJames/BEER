import Foundation
import XCTest
@testable import BEER

final class ControllerFixDetectionTests: XCTestCase {
    /// The report descriptor Steam for macOS publishes for a Steam Controller's
    /// virtual pad, as read from IOHID.
    private static let steamDescriptor = hexData(
        "05010905a1010501093aa102750895020501093f093b81017501150025013500450195040509190c290f8102"
        + "75011500250135004501950405090909090a090709088102750115002501350045019503050909050906090b"
        + "810275019501810175011500250135004501950405091901290481027508150026ff00350046ff0095020501"
        + "093209358102751016008026ff7f36008046ff7f05010901a10095020501093009318102c005010901a10095"
        + "020501093309348102c0c0c0"
    )

    private let steamPad = ControllerSupport.Gamepad(
        vendorID: 0x045e, productID: 0x028e, name: "GamePad-1", reportDescriptor: steamDescriptor
    )

    func testRecordedSteamDescriptorMatchesProfileFingerprint() {
        XCTAssertEqual(
            SHA256Digest.hexDigest(Self.steamDescriptor),
            ControllerFixProfiles.steamVirtualGamepad.descriptorSHA256
        )
    }

    func testSteamVirtualPadIsSupported() {
        XCTAssertEqual(
            ControllerSupport.detectFix(among: [steamPad]),
            .supported(ControllerFixProfiles.steamVirtualGamepad, steamPad)
        )
    }

    /// Same IDs, different layout: the measured bit offsets don't apply, so
    /// the fix must not guess.
    func testSameIDsWithDifferentDescriptorAreUnsupported() {
        var descriptor = Self.steamDescriptor
        descriptor[descriptor.startIndex + 20] ^= 0xff
        let lookalike = ControllerSupport.Gamepad(
            vendorID: 0x045e, productID: 0x028e, name: "Xbox 360 Controller", reportDescriptor: descriptor
        )

        XCTAssertEqual(ControllerSupport.detectFix(among: [lookalike]), .unsupported([lookalike]))
    }

    func testSameDescriptorWithDifferentIDsIsUnsupported() {
        let other = ControllerSupport.Gamepad(
            vendorID: 0x045e, productID: 0x0b13, name: "Xbox Wireless Controller", reportDescriptor: Self.steamDescriptor
        )

        XCTAssertEqual(ControllerSupport.detectFix(among: [other]), .unsupported([other]))
    }

    func testFindsSupportedPadAmongOthers() {
        let dualSense = ControllerSupport.Gamepad(
            vendorID: 0x054c, productID: 0x0ce6, name: "DualSense Wireless Controller", reportDescriptor: Data([0x05, 0x01])
        )

        XCTAssertEqual(
            ControllerSupport.detectFix(among: [dualSense, steamPad]),
            .supported(ControllerFixProfiles.steamVirtualGamepad, steamPad)
        )
    }

    func testNoPadsMeansNoGamepad() {
        XCTAssertEqual(ControllerSupport.detectFix(among: []), .noGamepad)
    }

    func testIdentifierIsLowercaseVidPid() {
        XCTAssertEqual(steamPad.identifier, "045e:028e")
    }

    // MARK: - PE machine

    func testReadsX86_64Machine() {
        XCTAssertEqual(ControllerSupport.peMachine(of: Self.peHeader(machine: 0x8664)), 0x8664)
    }

    func testReadsI386Machine() {
        XCTAssertEqual(ControllerSupport.peMachine(of: Self.peHeader(machine: 0x014c)), 0x014c)
    }

    func testRejectsNonPE() {
        XCTAssertNil(ControllerSupport.peMachine(of: Data(repeating: 0, count: 256)))
        XCTAssertNil(ControllerSupport.peMachine(of: Data([0x4d, 0x5a])))
    }

    func testRejectsPEOffsetPastHeader() {
        var header = Self.peHeader(machine: 0x8664)
        header[0x3c] = 0xff
        header[0x3d] = 0xff
        XCTAssertNil(ControllerSupport.peMachine(of: header))
    }

    func testDetectsExecutableArchitectureOnDisk() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).exe")
        try Self.peHeader(machine: 0x8664).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertTrue(ControllerSupport.isX86_64Executable(file.path))
        XCTAssertFalse(ControllerSupport.isX86_64Executable(file.path + ".missing"))
    }

    // MARK: - Helpers

    private static func peHeader(machine: UInt16) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0] = 0x4d
        bytes[1] = 0x5a
        bytes[0x3c] = 0x80
        bytes[0x80..<0x84] = [0x50, 0x45, 0, 0]
        bytes[0x84] = UInt8(machine & 0xff)
        bytes[0x85] = UInt8(machine >> 8)
        return Data(bytes)
    }

    private static func hexData(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }
}
