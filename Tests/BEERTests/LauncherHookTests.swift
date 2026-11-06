import XCTest
@testable import BEER

/// A launcher that starts the game's SteamStub-wrapped exe itself, as
/// Fallout4Launcher.exe starts Fallout4.exe, and F4SE started in the game.
/// Offline: headers are synthesized and the loader's and helpers' files are
/// empty stand-ins. The helpers themselves were run under Wine by hand.
final class LauncherHookTests: XCTestCase {
    private var root: URL!
    private var installDir: URL!
    private var loaderSource: URL!
    private var helpers: URL!
    private var launcher: URL { installDir.appendingPathComponent("Fallout4Launcher.exe") }
    private var game: URL { installDir.appendingPathComponent("Fallout4.exe") }
    private var folder: URL { installDir.appendingPathComponent(ColdClientApplicator.folderName) }
    private let wrapped = SteamStubTests.peHeader(machine: 0x8664, sections: [".text", ".rdata", ".bind"])
    private let plan = SteamClientLoaderPlan(is64Bit: true, patchesSteamStub: true, injectsOldSteamLibrary: false,
                                             injectsOverlay: false, staysOpen: false)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LauncherHookTests-\(UUID().uuidString)", isDirectory: true)
        installDir = root.appendingPathComponent("Fallout 4", isDirectory: true)
        loaderSource = root.appendingPathComponent("steamclient_experimental", isDirectory: true)
        helpers = root.appendingPathComponent("WindowsHelpers", isDirectory: true)
        let extras = loaderSource.appendingPathComponent("extra_dlls", isDirectory: true)
        for folder in [installDir!, extras, helpers!] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for name in ["steamclient.dll", "steamclient64.dll", "steamclient_loader_x86.exe", "steamclient_loader_x64.exe"] {
            try Data(name.utf8).write(to: loaderSource.appendingPathComponent(name))
        }
        try Data("steamclient_extra_x64.dll".utf8).write(to: extras.appendingPathComponent("steamclient_extra_x64.dll"))
        for name in [WindowsHelpers.launcher, WindowsHelpers.launchHook, WindowsHelpers.scriptExtenderStarter] {
            try Data(name.utf8).write(to: helpers.appendingPathComponent(name))
        }
        try SteamStubTests.peHeader(machine: 0x8664, sections: [".text", ".data"]).write(to: launcher)
        try wrapped.write(to: game)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func installF4SE() throws {
        try Data("f4se_loader".utf8).write(to: installDir.appendingPathComponent("f4se_loader.exe"))
        try Data("f4se".utf8).write(to: installDir.appendingPathComponent("f4se_1_11_240.dll"))
    }

    // MARK: - Launcher

    func testFindsTheWrappedGameBesideAnUnwrappedLauncher() {
        XCTAssertEqual(ColdClientApplicator.wrappedGame(beside: launcher)?.lastPathComponent, "Fallout4.exe")
        XCTAssertNil(ColdClientApplicator.wrappedGame(beside: game), "the game itself isn't its own companion")
    }

    func testNoWrappedGameNoHook() throws {
        try SteamStubTests.peHeader(machine: 0x8664, sections: [".text"]).write(to: game)
        XCTAssertNil(ColdClientApplicator.wrappedGame(beside: launcher))
    }

    /// The game's start goes to the loader; the game keeps its name and place.
    func testTheLauncherStartsTheGameThroughTheLoader() throws {
        let gameLoader = try ColdClientApplicator.prepare(executable: game, installDir: installDir, appID: 377160,
                                                          plan: plan, loaderSource: loaderSource, helpers: helpers)

        let started = try ColdClientApplicator.prepareLauncher(launcher, game: game, gameLoader: gameLoader,
                                                               installDir: installDir, helpers: helpers)

        XCTAssertEqual(started, folder.appendingPathComponent("beer_launch.exe"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("beer_launch_hook.dll").path))
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("beer_launch.txt"), encoding: .utf8),
                       "launch=..\\Fallout4Launcher.exe\nredirect=Fallout4.exe\nto=steamclient_loader_x64.exe\n")
        let ini = try String(contentsOf: folder.appendingPathComponent("ColdClientLoader.ini"), encoding: .utf8)
        XCTAssertTrue(ini.contains("Exe=..\\Fallout4.exe\n"))
        XCTAssertEqual(try Data(contentsOf: game), wrapped, "the game's exe is untouched")
    }

    func testALauncherInASubfolderIsFoundFromTheHelpersFolder() throws {
        let bin = installDir.appendingPathComponent("Bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let subLauncher = bin.appendingPathComponent("Launcher.exe")
        try Data().write(to: subLauncher)

        _ = try ColdClientApplicator.prepareLauncher(subLauncher, game: bin.appendingPathComponent("Game.exe"),
                                                     gameLoader: folder.appendingPathComponent("steamclient_loader_x64.exe"),
                                                     installDir: installDir, helpers: helpers)

        let config = try String(contentsOf: folder.appendingPathComponent("beer_launch.txt"), encoding: .utf8)
        XCTAssertTrue(config.hasPrefix("launch=..\\Bin\\Launcher.exe\nredirect=Game.exe\n"))
    }

    // MARK: - Script extender

    func testThePlanNotesAnInstalledF4SE() throws {
        let without = SteamClientLoaderPlan.make(executable: game, installDir: installDir, mode: .automatic)
        XCTAssertNil(without?.scriptExtender)

        try installF4SE()

        XCTAssertEqual(SteamClientLoaderPlan.make(executable: game, installDir: installDir, mode: .automatic)?.scriptExtender, "f4se")
    }

    /// f4se_loader.exe can't start the game past SteamStub, so the loader
    /// starts F4SE itself, after the stub patch.
    func testF4SEStartsInTheGameAfterTheStubPatch() throws {
        var withF4SE = plan
        withF4SE.scriptExtender = "f4se"

        _ = try ColdClientApplicator.prepare(executable: game, installDir: installDir, appID: 377160,
                                             plan: withF4SE, loaderSource: loaderSource, helpers: helpers)

        let extras = folder.appendingPathComponent("extra_dlls")
        XCTAssertEqual(try Data(contentsOf: extras.appendingPathComponent("beer_xse_start.dll")), Data("beer_xse_start.dll".utf8))
        XCTAssertEqual(try String(contentsOf: extras.appendingPathComponent("beer_xse_start.txt"), encoding: .utf8), "prefix=f4se\n")
        XCTAssertEqual(try String(contentsOf: extras.appendingPathComponent("load_order.txt"), encoding: .utf8),
                       "steamclient_extra_x64.dll\nbeer_xse_start.dll\n")
    }

    /// Without the helpers (a `swift run` build that hasn't built them) the game still runs, without F4SE.
    func testMissingHelpersStillLaunchWithoutF4SE() throws {
        var withF4SE = plan
        withF4SE.scriptExtender = "f4se"

        _ = try ColdClientApplicator.prepare(executable: game, installDir: installDir, appID: 377160,
                                             plan: withF4SE, loaderSource: loaderSource, helpers: nil)

        let extras = folder.appendingPathComponent("extra_dlls")
        XCTAssertFalse(FileManager.default.fileExists(atPath: extras.appendingPathComponent("beer_xse_start.dll").path))
        XCTAssertEqual(try String(contentsOf: extras.appendingPathComponent("load_order.txt"), encoding: .utf8),
                       "steamclient_extra_x64.dll\n")
    }

    func testFindsF4SEByItsLoader() throws {
        XCTAssertNil(ScriptExtender.prefix(in: installDir))
        try installF4SE()
        XCTAssertEqual(ScriptExtender.prefix(in: installDir), "f4se")
    }
}
