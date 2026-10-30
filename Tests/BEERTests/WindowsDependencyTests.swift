import XCTest
@testable import BEER

final class WindowsDependencyTests: XCTestCase {
    private var prefix: URL!

    override func setUpWithError() throws {
        prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowsDependencyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: prefix)
    }

    // MARK: - Manifest

    func testEveryPackageIsFromMicrosoftOverHTTPS() {
        for dependency in WindowsDependency.allCases {
            XCTAssertFalse(dependency.packages.isEmpty, "\(dependency) has nothing to install")
            for package in dependency.packages {
                XCTAssertTrue(package.isFromOfficialHost, "\(package.url) is not a Microsoft download host")
            }
        }
    }

    func testEveryHashIsLowercaseSHA256() {
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        for package in WindowsDependency.allCases.flatMap(\.packages) {
            XCTAssertEqual(package.sha256.count, 64, package.fileName)
            XCTAssertTrue(package.sha256.unicodeScalars.allSatisfy(hex.contains), package.fileName)
            XCTAssertGreaterThan(package.size, 0, package.fileName)
        }
    }

    /// Microsoft puts the file's SHA-256 in versioned VC++ download paths; the
    /// pinned hash must be that one, or we've pasted a hash for the wrong file.
    func testVCRedistHashMatchesTheOneInItsURL() {
        for package in WindowsDependency.vcRedist.packages {
            let components = package.url.pathComponents.map { $0.lowercased() }
            XCTAssertTrue(components.contains(package.sha256), package.url.absoluteString)
            XCTAssertEqual(package.url.lastPathComponent, package.fileName)
        }
    }

    func testVCRedistCoversBothArchitectures() {
        let names = WindowsDependency.vcRedist.packages.map(\.fileName)
        XCTAssertEqual(names, ["VC_redist.x86.exe", "VC_redist.x64.exe"])
    }

    func testRejectsNonMicrosoftAndPlainHTTPHosts() {
        let mirror = package(url: "https://files.example.org/directx_Jun2010_redist.exe")
        let http = package(url: "http://download.microsoft.com/directx_Jun2010_redist.exe")
        let shortlink = package(url: "https://aka.ms/vc14/vc_redist.x64.exe")
        XCTAssertFalse(mirror.isFromOfficialHost)
        XCTAssertFalse(http.isFromOfficialHost)
        XCTAssertFalse(shortlink.isFromOfficialHost)
    }

    // MARK: - Exit codes

    func testAcceptsRebootAndAlreadyInstalledCodesEvenTruncatedByWine() {
        let vc = WindowsDependencyManifest.vcRedistX64
        XCTAssertTrue(vc.isSuccess(exitCode: 0))
        XCTAssertTrue(vc.isSuccess(exitCode: 3010))
        XCTAssertTrue(vc.isSuccess(exitCode: 3010 & 0xFF))
        XCTAssertTrue(vc.isSuccess(exitCode: 1638 & 0xFF))
        XCTAssertFalse(vc.isSuccess(exitCode: 1))
        XCTAssertFalse(vc.isSuccess(exitCode: 1603 & 0xFF))
    }

    // MARK: - Receipt and winetricks.log

    func testReceiptRoundTripsAndIgnoresUnknownLines() {
        var text = WindowsDependencyDetector.receipt(byAdding: .vcRedist, to: "")
        text = WindowsDependencyDetector.receipt(byAdding: .vcRedist, to: text)
        text = WindowsDependencyDetector.receipt(byAdding: .directX, to: text + "dotnet48\n")
        XCTAssertEqual(text.components(separatedBy: "vcRedist").count, 2, "recorded twice")
        XCTAssertEqual(WindowsDependencyDetector.parseReceipt(text), [.vcRedist, .directX])
    }

    func testWinetricksLogVerbsMapToDependencies() {
        XCTAssertEqual(WindowsDependencyDetector.parseWinetricksLog("corefonts\nvcrun2022\n"), [.vcRedist])
        XCTAssertEqual(WindowsDependencyDetector.parseWinetricksLog("d3dx9\r\n"), [.directX])
        XCTAssertEqual(WindowsDependencyDetector.parseWinetricksLog("vcrun2008\ndxvk\n"), [])
    }

    // MARK: - DLL inspection

    func testRecognisesWineBuiltinStub() throws {
        let builtin = try writeDLL("drive_c/windows/system32/msvcp140.dll", stub: "Wine builtin DLL")
        let placeholder = try writeDLL("drive_c/windows/system32/old.dll", stub: "Wine placeholder DLL")
        let native = try writeDLL("drive_c/windows/system32/real.dll", stub: "This program cannot be run")
        XCTAssertTrue(WindowsDependencyDetector.isWineBuiltin(builtin))
        XCTAssertTrue(WindowsDependencyDetector.isWineBuiltin(placeholder))
        XCTAssertFalse(WindowsDependencyDetector.isWineBuiltin(native))
        XCTAssertTrue(WindowsDependencyDetector.isNativeDLL(native))
        XCTAssertFalse(WindowsDependencyDetector.isNativeDLL(prefix.appendingPathComponent("missing.dll")))
    }

    func testFreshPrefixHasNothingInstalled() throws {
        try writeDLL("drive_c/windows/system32/vcruntime140.dll", stub: "Wine builtin DLL")
        try writeDLL("drive_c/windows/syswow64/vcruntime140.dll", stub: "Wine builtin DLL")
        XCTAssertEqual(WindowsDependencyDetector.installed(inPrefix: prefix), [])
    }

    func testNativeVCRuntimeNeedsBothArchitectures() throws {
        try writeDLL("drive_c/windows/system32/vcruntime140.dll", stub: "This program cannot be run")
        try writeDLL("drive_c/windows/syswow64/vcruntime140.dll", stub: "Wine builtin DLL")
        XCTAssertFalse(WindowsDependencyDetector.installed(inPrefix: prefix).contains(.vcRedist))

        try writeDLL("drive_c/windows/syswow64/vcruntime140.dll", stub: "This program cannot be run")
        XCTAssertTrue(WindowsDependencyDetector.installed(inPrefix: prefix).contains(.vcRedist))
    }

    func testDetectsReceiptAndWinetricksLogInPrefix() throws {
        try "directX\n".write(to: prefix.appendingPathComponent(WindowsDependencyDetector.receiptFileName), atomically: true, encoding: .utf8)
        try "vcrun2019\n".write(to: prefix.appendingPathComponent(WindowsDependencyDetector.winetricksLogFileName), atomically: true, encoding: .utf8)
        XCTAssertEqual(WindowsDependencyDetector.installed(inPrefix: prefix), [.vcRedist, .directX])
    }

    // MARK: - DLL overrides

    @MainActor
    func testOverrideRegistryFileSetsNativeThenBuiltin() {
        let reg = WindowsDependencyInstaller.dllOverrideRegistry(["msvcp140", "vcruntime140_1"])
        XCTAssertEqual(reg, """
        REGEDIT4

        [HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]
        "msvcp140"="native,builtin"
        "vcruntime140_1"="native,builtin"

        """)
    }

    func testPlaceholderListOnlyTouchesSystemDirectories() {
        for directory in WindowsDependencyManifest.vcRedistPlaceholderDLLs.keys {
            XCTAssertTrue(["drive_c/windows/system32", "drive_c/windows/syswow64"].contains(directory), directory)
        }
    }

    // MARK: - Helpers

    private func package(url: String) -> RedistributablePackage {
        RedistributablePackage(
            fileName: "x.exe", url: URL(string: url)!, sha256: String(repeating: "0", count: 64),
            size: 1, installArguments: [], successExitCodes: [0]
        )
    }

    /// A file with a DOS-header-sized prefix, then `stub` at offset 0x40 —
    /// where Wine writes its builtin marker.
    @discardableResult
    private func writeDLL(_ relativePath: String, stub: String) throws -> URL {
        let url = prefix.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data("MZ".utf8) + Data(count: 0x40 - 2)
        data.append(Data(stub.utf8))
        data.append(Data(count: 64))
        try data.write(to: url)
        return url
    }
}
