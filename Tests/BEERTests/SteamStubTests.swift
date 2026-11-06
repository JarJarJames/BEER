import XCTest
@testable import BEER

/// Detecting SteamStub and laying out ColdClientLoader. Offline: headers are
/// synthesized and the loader's files are empty stand-ins.
final class SteamStubTests: XCTestCase {
    private var root: URL!
    private var installDir: URL!
    private var loaderSource: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteamStubTests-\(UUID().uuidString)", isDirectory: true)
        installDir = root.appendingPathComponent("Game", isDirectory: true)
        loaderSource = root.appendingPathComponent("steamclient_experimental", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: loaderSource, withIntermediateDirectories: true)
        for name in ["steamclient.dll", "steamclient64.dll", "GameOverlayRenderer.dll", "GameOverlayRenderer64.dll",
                     "steamclient_loader_x86.exe", "steamclient_loader_x64.exe"] {
            try Data(name.utf8).write(to: loaderSource.appendingPathComponent(name))
        }
        let extras = loaderSource.appendingPathComponent("extra_dlls", isDirectory: true)
        try FileManager.default.createDirectory(at: extras, withIntermediateDirectories: true)
        for name in ["steamclient_extra_x86.dll", "steamclient_extra_x64.dll"] {
            try Data(name.utf8).write(to: extras.appendingPathComponent(name))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - PE header

    func testDetectsTheBindSectionOnA32BitExe() throws {
        let header = try XCTUnwrap(PortableExecutable(header: Self.peHeader(machine: 0x14C, sections: [".text", ".rdata", ".bind"])))

        XCTAssertFalse(header.is64Bit)
        XCTAssertTrue(header.isSteamStubWrapped)
    }

    func testAnUnwrapped64BitExeIsNotFlagged() throws {
        let header = try XCTUnwrap(PortableExecutable(header: Self.peHeader(machine: 0x8664, sections: [".text", ".data"])))

        XCTAssertTrue(header.is64Bit)
        XCTAssertFalse(header.isSteamStubWrapped)
        XCTAssertEqual(header.sectionNames, [".text", ".data"])
    }

    func testRejectsFilesThatAreNotExecutables() {
        XCTAssertNil(PortableExecutable(header: Data("not an exe".utf8)))
        XCTAssertNil(PortableExecutable(header: Data([0x4D, 0x5A])))
    }

    func testReadsTheHeaderFromDisk() throws {
        let exe = installDir.appendingPathComponent("isaac-ng.exe")
        try Self.peHeader(machine: 0x14C, sections: [".text", ".bind"]).write(to: exe)

        XCTAssertEqual(PortableExecutable(contentsOf: exe)?.isSteamStubWrapped, true)
    }

    // MARK: - Loader layout

    func testPreparesTheLoaderForA32BitGame() throws {
        let exe = installDir.appendingPathComponent("isaac-ng.exe")
        try Data().write(to: exe)
        let settings = installDir.appendingPathComponent("steam_settings", isDirectory: true)
        try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: true)
        try "250900".write(to: settings.appendingPathComponent("steam_appid.txt"), atomically: true, encoding: .utf8)

        let loader = try ColdClientApplicator.prepare(
            executable: exe, installDir: installDir, appID: 250900, plan: .stub32, loaderSource: loaderSource
        )

        let folder = installDir.appendingPathComponent(ColdClientApplicator.folderName)
        XCTAssertEqual(loader.lastPathComponent, "steamclient_loader_x86.exe")
        for name in ["steamclient.dll", "steamclient64.dll", "GameOverlayRenderer.dll", "steam_settings/steam_appid.txt",
                     "extra_dlls/steamclient_extra_x86.dll"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path), name)
        }
        let ini = try String(contentsOf: folder.appendingPathComponent(ColdClientApplicator.configFile), encoding: .utf8)
        XCTAssertTrue(ini.contains("Exe=..\\isaac-ng.exe\n"))
        XCTAssertTrue(ini.contains("AppId=250900\n"))
        XCTAssertTrue(ini.contains("DllsToInjectFolder=extra_dlls\n"))
    }

    func testPreparingTwiceReplacesTheOldCopy() throws {
        let exe = installDir.appendingPathComponent("isaac-ng.exe")
        try Data().write(to: exe)

        _ = try ColdClientApplicator.prepare(executable: exe, installDir: installDir, appID: 1, plan: .stub32, loaderSource: loaderSource)
        let loader = try ColdClientApplicator.prepare(executable: exe, installDir: installDir, appID: 1, plan: .stub64, loaderSource: loaderSource)

        XCTAssertEqual(loader.lastPathComponent, "steamclient_loader_x64.exe")
        let extras = installDir.appendingPathComponent("\(ColdClientApplicator.folderName)/extra_dlls")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: extras.path).sorted(), ["load_order.txt", "steamclient_extra_x64.dll"])
    }

    /// Regression: the ~44 MB of emulator DLLs were copied again on every
    /// launch, which froze BEER for seconds with the game on a USB drive.
    func testUnchangedEmulatorFilesAreNotCopiedAgain() throws {
        let exe = installDir.appendingPathComponent("isaac-ng.exe")
        try Data().write(to: exe)
        let copy = installDir.appendingPathComponent("\(ColdClientApplicator.folderName)/steamclient.dll")

        _ = try ColdClientApplicator.prepare(executable: exe, installDir: installDir, appID: 1, plan: .stub32, loaderSource: loaderSource)
        let first = try fileNumber(of: copy)
        _ = try ColdClientApplicator.prepare(executable: exe, installDir: installDir, appID: 1, plan: .stub32, loaderSource: loaderSource)

        XCTAssertEqual(try fileNumber(of: copy), first, "the same file, not a fresh copy")
    }

    func testANewEmulatorReleaseReplacesTheCopy() throws {
        let exe = installDir.appendingPathComponent("isaac-ng.exe")
        try Data().write(to: exe)
        let source = loaderSource.appendingPathComponent("steamclient.dll")
        let copy = installDir.appendingPathComponent("\(ColdClientApplicator.folderName)/steamclient.dll")
        _ = try ColdClientApplicator.prepare(executable: exe, installDir: installDir, appID: 1, plan: .stub32, loaderSource: loaderSource)

        try Data("steamclient.dll, newer build".utf8).write(to: source)
        _ = try ColdClientApplicator.prepare(executable: exe, installDir: installDir, appID: 1, plan: .stub32, loaderSource: loaderSource)

        XCTAssertEqual(try Data(contentsOf: copy), Data("steamclient.dll, newer build".utf8))
    }

    /// Same size isn't enough: a rebuild can keep the size and change the date.
    func testSameSizeButNewerSourceIsNotTheSameFile() throws {
        let source = loaderSource.appendingPathComponent("steamclient.dll")
        let copy = root.appendingPathComponent("copy.dll")
        try FileManager.default.copyItem(at: source, to: copy)
        XCTAssertTrue(ColdClientApplicator.isSameFile(copy, as: source))

        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: source.path)

        XCTAssertFalse(ColdClientApplicator.isSameFile(copy, as: source))
        XCTAssertFalse(ColdClientApplicator.isSameFile(root.appendingPathComponent("missing.dll"), as: source))
    }

    func testMissingSteamclientIsAnError() throws {
        try FileManager.default.removeItem(at: loaderSource.appendingPathComponent("steamclient.dll"))
        let exe = installDir.appendingPathComponent("game.exe")
        try Data().write(to: exe)

        XCTAssertThrowsError(try ColdClientApplicator.prepare(
            executable: exe, installDir: installDir, appID: 1, plan: .stub32, loaderSource: loaderSource
        ))
    }

    func testWindowsPathIsRelativeToTheInstall() {
        let exe = installDir.appendingPathComponent("Bin/Win32/Game.exe")

        XCTAssertEqual(ColdClientApplicator.windowsPath(of: exe, relativeTo: installDir), "Bin\\Win32\\Game.exe")
        XCTAssertNil(ColdClientApplicator.windowsPath(of: root.appendingPathComponent("Other.exe"), relativeTo: installDir))
    }

    func testRestoringTheEmulatorRemovesTheLoader() throws {
        let exe = installDir.appendingPathComponent("game.exe")
        try Data().write(to: exe)
        _ = try ColdClientApplicator.prepare(executable: exe, installDir: installDir, appID: 1, plan: .stub32, loaderSource: loaderSource)

        _ = try GoldbergApplicator.restore(installDir: installDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.appendingPathComponent(ColdClientApplicator.folderName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exe.path))
    }

    func testOldSteamLibraryIsForceInjectedAfterTheStubPatch() throws {
        let exe = installDir.appendingPathComponent("hl.exe")
        try Data().write(to: exe)
        let oldLibrary = root.appendingPathComponent("steam_old_lib/Steam.dll")
        try FileManager.default.createDirectory(at: oldLibrary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldLibrary)
        let plan = SteamClientLoaderPlan(is64Bit: false, patchesSteamStub: true, injectsOldSteamLibrary: true, injectsOverlay: false, staysOpen: false)

        _ = try ColdClientApplicator.prepare(
            executable: exe, installDir: installDir, appID: 70, plan: plan,
            loaderSource: loaderSource, oldSteamLibrary: oldLibrary
        )

        let folder = installDir.appendingPathComponent(ColdClientApplicator.folderName)
        let order = try String(contentsOf: folder.appendingPathComponent("extra_dlls/load_order.txt"), encoding: .utf8)
        XCTAssertEqual(order, "steamclient_extra_x86.dll\nSteam.dll\n")
        let ini = try String(contentsOf: folder.appendingPathComponent(ColdClientApplicator.configFile), encoding: .utf8)
        XCTAssertTrue(ini.contains("ForceInjectSteamClient=1\n"))
    }

    func testMissingOldSteamLibraryIsAnError() throws {
        let exe = installDir.appendingPathComponent("hl.exe")
        try Data().write(to: exe)
        let plan = SteamClientLoaderPlan(is64Bit: false, patchesSteamStub: false, injectsOldSteamLibrary: true, injectsOverlay: false, staysOpen: false)

        XCTAssertThrowsError(try ColdClientApplicator.prepare(
            executable: exe, installDir: installDir, appID: 70, plan: plan, loaderSource: loaderSource
        ))
    }

    func testOverlayAndStayOpenOptionsReachTheIni() {
        let plan = SteamClientLoaderPlan(is64Bit: true, patchesSteamStub: false, injectsOldSteamLibrary: false, injectsOverlay: true, staysOpen: true)

        let ini = ColdClientApplicator.configuration(executablePath: "game.exe", appID: 1, plan: plan)

        XCTAssertTrue(ini.contains("ForceInjectSteamClient=0\n"))
        XCTAssertTrue(ini.contains("ForceInjectGameOverlayRenderer=1\n"))
        XCTAssertTrue(ini.contains("[Persistence]\nMode=1\n"))
    }

    func testAGameWithNoSettingsOfItsOwnGetsFreshOnes() throws {
        let exe = installDir.appendingPathComponent("game.exe")
        try Data().write(to: exe)

        _ = try ColdClientApplicator.prepare(
            executable: exe, installDir: installDir, appID: 4000, plan: .stub64, loaderSource: loaderSource,
            writeSettings: { folder in
                try GoldbergApplicator.writeSteamSettings(in: folder, appID: 4000, account: "player", steamID64: "76561197960287930", dlc: [])
            }
        )

        let settings = installDir.appendingPathComponent("\(ColdClientApplicator.folderName)/steam_settings")
        XCTAssertEqual(try String(contentsOf: settings.appendingPathComponent("steam_appid.txt"), encoding: .utf8), "4000")
        let user = try String(contentsOf: settings.appendingPathComponent("configs.user.ini"), encoding: .utf8)
        XCTAssertTrue(user.contains("account_steamid=76561197960287930"))
    }

    // MARK: - When to use the loader

    func testPlanIsNilForAnOrdinaryGame() throws {
        let exe = try makeExe("game.exe", machine: 0x8664, sections: [".text"])
        try Data().write(to: installDir.appendingPathComponent("steam_api64.dll"))

        XCTAssertNil(SteamClientLoaderPlan.make(executable: exe, installDir: installDir, mode: .automatic))
    }

    func testPlanPatchesAWrappedExe() throws {
        let exe = try makeExe("isaac-ng.exe", machine: 0x14C, sections: [".text", ".bind"])
        try Data().write(to: installDir.appendingPathComponent("steam_api.dll"))

        let plan = try XCTUnwrap(SteamClientLoaderPlan.make(executable: exe, installDir: installDir, mode: .automatic))

        XCTAssertTrue(plan.patchesSteamStub)
        XCTAssertFalse(plan.injectsOldSteamLibrary)
        XCTAssertFalse(plan.is64Bit)
    }

    func testPlanInjectsTheOldLibraryBesideA32BitExe() throws {
        let exe = try makeExe("hl.exe", machine: 0x14C, sections: [".text"])
        try Data().write(to: installDir.appendingPathComponent("steam.DLL"))

        let plan = try XCTUnwrap(SteamClientLoaderPlan.make(executable: exe, installDir: installDir, mode: .automatic))

        XCTAssertTrue(plan.injectsOldSteamLibrary)
        XCTAssertFalse(plan.patchesSteamStub)
    }

    func testPlanCoversAGameThatLoadsSteamClientItself() throws {
        var exeData = Self.peHeader(machine: 0x8664, sections: [".text"])
        exeData.append(Data("\0SteamClient017\0".utf8))
        let exe = installDir.appendingPathComponent("game.exe")
        try exeData.write(to: exe)

        XCTAssertNotNil(SteamClientLoaderPlan.make(executable: exe, installDir: installDir, mode: .automatic))

        // The same exe beside a steam_api.dll goes through that instead.
        try Data().write(to: installDir.appendingPathComponent("steam_api64.dll"))
        XCTAssertNil(SteamClientLoaderPlan.make(executable: exe, installDir: installDir, mode: .automatic))
    }

    func testDRMFreeGameWithNoSteamAPIRunsDirectly() throws {
        let exe = try makeExe("game.exe", machine: 0x8664, sections: [".text"])

        XCTAssertNil(SteamClientLoaderPlan.make(executable: exe, installDir: installDir, mode: .automatic))
    }

    func testModeOverridesDetection() throws {
        let plain = try makeExe("game.exe", machine: 0x8664, sections: [".text"])
        let wrapped = try makeExe("wrapped.exe", machine: 0x8664, sections: [".bind"])

        let forced = try XCTUnwrap(SteamClientLoaderPlan.make(
            executable: plain, installDir: installDir, mode: .always, injectsOverlay: true, staysOpen: true
        ))
        XCTAssertTrue(forced.injectsOverlay)
        XCTAssertTrue(forced.staysOpen)
        XCTAssertNil(SteamClientLoaderPlan.make(executable: wrapped, installDir: installDir, mode: .off))
    }

    /// Identifies the file itself; a copy over it gets a new one.
    private func fileNumber(of url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int)
    }

    private func makeExe(_ name: String, machine: UInt16, sections: [String]) throws -> URL {
        let url = installDir.appendingPathComponent(name)
        try Self.peHeader(machine: machine, sections: sections).write(to: url)
        return url
    }

    /// A minimal PE header: DOS stub pointing at a COFF header with no
    /// optional header, followed by the section table.
    private static func peHeader(machine: UInt16, sections: [String]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x80)
        bytes[0] = 0x4D; bytes[1] = 0x5A
        bytes[0x3C] = 0x80
        bytes += [0x50, 0x45, 0, 0]
        bytes += [UInt8(machine & 0xFF), UInt8(machine >> 8)]
        bytes += [UInt8(sections.count), 0]
        bytes += [UInt8](repeating: 0, count: 12)
        bytes += [0, 0, 0, 0]  // optional header size 0, characteristics
        for name in sections {
            var entry = [UInt8](name.utf8.prefix(8))
            entry += [UInt8](repeating: 0, count: 40 - entry.count)
            bytes += entry
        }
        return Data(bytes)
    }
}

private extension SteamClientLoaderPlan {
    static let stub32 = SteamClientLoaderPlan(is64Bit: false, patchesSteamStub: true, injectsOldSteamLibrary: false, injectsOverlay: false, staysOpen: false)
    static let stub64 = SteamClientLoaderPlan(is64Bit: true, patchesSteamStub: true, injectsOldSteamLibrary: false, injectsOverlay: false, staysOpen: false)
}
