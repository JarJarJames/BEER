import XCTest
@testable import BEER

/// The port of gbe_fork's `generate_interfaces`, run on synthesized DLL bytes.
final class SteamInterfacesScannerTests: XCTestCase {
    private func dll(_ strings: [String]) -> Data {
        var data = Data([0x4D, 0x5A, 0x90, 0x00, 0xFF, 0xFE])
        for string in strings {
            data.append(Data(string.utf8))
            data.append(contentsOf: [0x00, 0xC3, 0x00])
        }
        return data
    }

    func testFindsVersionsInTheToolsOrder() {
        let found = SteamInterfacesScanner.interfaces(in: dll([
            "SteamUtils008", "SteamUser019", "STEAMAPPS_INTERFACE_VERSION008", "SteamClient017",
        ]))

        XCTAssertEqual(found, ["STEAMAPPS_INTERFACE_VERSION008", "SteamClient017", "SteamUser019", "SteamUtils008"])
    }

    func testKeepsOnlySteamClient017WhenItIsPresent() {
        let found = SteamInterfacesScanner.interfaces(in: dll(["SteamClient012", "SteamClient017", "SteamClient020"]))

        XCTAssertEqual(found, ["SteamClient017"])
    }

    func testKeepsOtherSteamClientVersionsWithout017() {
        let found = SteamInterfacesScanner.interfaces(in: dll(["SteamClient012", "SteamClient016"]))

        XCTAssertEqual(found, ["SteamClient012", "SteamClient016"])
    }

    func testLongerNamesAreNotMistakenForShorterOnes() {
        let found = SteamInterfacesScanner.interfaces(in: dll([
            "SteamGameServerStats001", "SteamNetworkingSockets012", "SteamMatchMakingServers002",
        ]))

        XCTAssertEqual(found, ["SteamGameServerStats001", "SteamMatchMakingServers002", "SteamNetworkingSockets012"])
    }

    func testDuplicatesAreDropped() {
        XCTAssertEqual(SteamInterfacesScanner.interfaces(in: dll(["SteamUser019", "SteamUser019"])), ["SteamUser019"])
    }

    func testNothingInADllWithoutInterfaces() {
        XCTAssertEqual(SteamInterfacesScanner.interfaces(in: dll(["kernel32.dll", "Steam"])), [])
    }
}
