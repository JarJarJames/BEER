import XCTest
@testable import BEER

final class SteamRedistTests: XCTestCase {
    private var gameDirectory: URL!

    override func setUpWithError() throws {
        gameDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteamRedistTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: gameDirectory)
    }

    // Shipped by Steam's VC++ 2010 depot (228983), signature block included.
    private let vcRedist2010 = #"""
    "installscript"
    {
    	"Run Process"
    	{
    		"x86"
    		{
    			"hasrunkey"		"HKEY_LOCAL_MACHINE\\Software\\Valve\\Steam\\Apps\\CommonRedist\\vcredist\\2010"
    			"process 1"		"%INSTALLDIR%\\_CommonRedist\\vcredist\\2010\\vcredist_x86.exe"
    			"command 1"		"/quiet /norestart"
    			"nocleanup"		"1"
    		}
    		"x64"
    		{
    			"hasrunkey"		"HKEY_LOCAL_MACHINE\\Software\\Valve\\Steam\\Apps\\CommonRedist\\vcredist\\2010"
    			"process 1"		"%INSTALLDIR%\\_CommonRedist\\vcredist\\2010\\vcredist_x64.exe"
    			"command 1"		"/quiet /norestart"
    			"nocleanup"		"1"
    			"requirement_os"
    			{
    				"is64bitwindows"		"1"
    			}
    		}
    	}
    }
    "kvsignatures"
    {
    	"installscript"		"21f349f31bf6d900"
    }
    """#

    // MARK: - KeyValues

    func testParsesNestedObjectsCaseInsensitively() {
        let root = KeyValues.parse(#""InstallScript" { "Registry" { "a" "1" } }"#)
        XCTAssertEqual(root["installscript"]?["registry"]?["A"]?.string, "1")
    }

    func testUnescapesBackslashesAndQuotes() {
        let root = KeyValues.parse(#""k" "C:\\Games\\\"x\"""#)
        XCTAssertEqual(root["k"]?.string, #"C:\Games\"x""#)
    }

    func testSkipsCommentsConditionalsAndBareTokens() {
        let root = KeyValues.parse("""
        // a comment
        root { key value [$WIN32] other "two words" }
        """)
        XCTAssertEqual(root["root"]?["key"]?.string, "value")
        XCTAssertEqual(root["root"]?["other"]?.string, "two words")
    }

    func testMalformedInputKeepsWhatParsed() {
        let root = KeyValues.parse(#""a" "1" "b" { "c" "2""#)
        XCTAssertEqual(root["a"]?.string, "1")
        XCTAssertEqual(root["b"]?["c"]?.string, "2")
    }

    // MARK: - SteamInstallScript

    func testReadsBothVCRedistEntriesWithInstallDirExpanded() {
        let script = SteamInstallScript(parsing: vcRedist2010, installDirectory: #"Z:\Games\Kenshi"#)
        XCTAssertEqual(script.runProcesses.map(\.name), ["x86", "x64"])

        let x64 = script.runProcesses[1]
        XCTAssertEqual(x64.hasRunKey, #"HKEY_LOCAL_MACHINE\Software\Valve\Steam\Apps\CommonRedist\vcredist\2010"#)
        XCTAssertEqual(x64.commands, [.init(
            executable: #"Z:\Games\Kenshi\_CommonRedist\vcredist\2010\vcredist_x64.exe"#,
            arguments: ["/quiet", "/norestart"]
        )])
    }

    func testSkipsEntriesThatRequire32BitWindows() {
        let text = #"""
        "installscript" { "Run Process" {
            "old" { "process 1" "a.exe" "requirement_os" { "is64bitwindows" "0" } }
            "new" { "process 1" "b.exe" }
        } }
        """#
        XCTAssertEqual(SteamInstallScript(parsing: text, installDirectory: "C:").runProcesses.map(\.name), ["new"])
    }

    func testRunsNumberedCommandsInOrder() {
        let text = #"""
        "installscript" { "Run Process" { "p" {
            "process 1" "one.exe" "process 2" "two.exe" "command 2" "/s \"%INSTALLDIR%\\a b\""
        } } }
        """#
        let commands = SteamInstallScript(parsing: text, installDirectory: #"C:\G"#).runProcesses.first?.commands
        XCTAssertEqual(commands, [
            .init(executable: "one.exe", arguments: []),
            .init(executable: "two.exe", arguments: ["/s", #"C:\G\a b"#]),
        ])
    }

    /// The game's own script (Spacewar's) only writes registry values, which
    /// BEER doesn't apply, so there is nothing to run.
    func testRegistryOnlyScriptHasNothingToRun() {
        let text = #""InstallScript" { "Registry" { "HKEY_LOCAL_MACHINE\\SOFTWARE\\Valve\\Spacewar" { "dword" { "PatchVersion" "42" } } } }"#
        XCTAssertTrue(SteamInstallScript(parsing: text, installDirectory: "C:").runProcesses.isEmpty)
    }

    // MARK: - SteamRedist

    func testFindsScriptsUnderCommonRedistOnly() throws {
        for path in ["_CommonRedist/vcredist/2010", "_CommonRedist/DirectX/Jun2010", "_CommonRedist/DotNet/4.0 Client Profile", "data"] {
            let folder = gameDirectory.appendingPathComponent(path, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "".write(to: folder.appendingPathComponent("installscript.vdf"), atomically: true, encoding: .utf8)
        }
        try "".write(to: gameDirectory.appendingPathComponent("installscript.vdf"), atomically: true, encoding: .utf8)

        let scripts = SteamRedist.installScripts(in: gameDirectory)
        XCTAssertEqual(scripts, [
            "_CommonRedist/DirectX/Jun2010/installscript.vdf",
            "_CommonRedist/DotNet/4.0 Client Profile/installscript.vdf",
            "_CommonRedist/vcredist/2010/installscript.vdf",
        ])
        XCTAssertEqual(scripts.filter { !SteamRedist.isSkipped($0) }.count, 2, ".NET is never run")
    }

    func testNoCommonRedistMeansNoScripts() {
        XCTAssertEqual(SteamRedist.installScripts(in: gameDirectory), [])
    }

    func testVCRedistYearComesFromTheFolder() {
        XCTAssertEqual(SteamRedist.vcRedistYear(ofScript: "_CommonRedist/vcredist/2010/installscript.vdf"), "2010")
        XCTAssertNil(SteamRedist.vcRedistYear(ofScript: "_CommonRedist/DirectX/Jun2010/installscript.vdf"))
    }

    func testReceiptRoundTripsAndSeparatesArchitectures() {
        let script = SteamInstallScript(parsing: vcRedist2010, installDirectory: "C:")
        let ids = Set(script.runProcesses.map { SteamRedist.receiptID(for: $0, scriptPath: "_CommonRedist/vcredist/2010/installscript.vdf") })
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(SteamRedist.parseReceipt(SteamRedist.receipt(ids)), ids)
    }

    func testWindowsPathGoesThroughZDrive() {
        XCTAssertEqual(SteamRedist.windowsPath(URL(fileURLWithPath: "/Users/me/Games/Kenshi")), #"Z:\Users\me\Games\Kenshi"#)
    }

    // MARK: - VC++ runtimes

    func testVC2010CoversKenshisMissingDLLs() {
        let dlls = WindowsDependencyManifest.steamVCRuntimeDLLs(year: "2010")
        XCTAssertTrue(dlls.contains("mfc100u"))
        XCTAssertTrue(dlls.contains("msvcp100"))
        XCTAssertEqual(WindowsDependencyManifest.steamVCPlaceholderDLLs(year: "2010")["drive_c/windows/system32"]?.contains("mfc100u.dll"), true)
    }

    func testVC14YearsReuseTheExistingLists() {
        XCTAssertEqual(WindowsDependencyManifest.steamVCRuntimeDLLs(year: "2022"), WindowsDependencyManifest.vcRedistDLLOverrides)
        XCTAssertEqual(WindowsDependencyManifest.steamVCPlaceholderDLLs(year: "2015"), WindowsDependencyManifest.vcRedistPlaceholderDLLs)
        XCTAssertEqual(WindowsDependencyManifest.steamVCRuntimeDLLs(year: "2008"), [])
    }
}
