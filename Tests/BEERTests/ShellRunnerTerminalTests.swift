import XCTest
@testable import BEER

/// `ShellRunner.run(terminal:)` gives the child a terminal on stdin and
/// stdout, which DepotDownloader checks before it reports progress, and
/// still returns once the child exits.
final class ShellRunnerTerminalTests: XCTestCase {
    private let check = ["-c", "test -t 0 && test -t 1 && echo terminal; exit 3"]

    func testTheChildSeesATerminal() async throws {
        let result = try await ShellRunner.run(executable: "/bin/sh", arguments: check, environment: [:],
                                               terminal: true) { _ in }
        XCTAssertTrue(result.output.contains("terminal"))
        XCTAssertEqual(result.exitCode, 3)
    }

    func testWithoutItTheChildSeesAPipe() async throws {
        let result = try await ShellRunner.run(executable: "/bin/sh", arguments: check, environment: [:]) { _ in }
        XCTAssertFalse(result.output.contains("terminal"))
        XCTAssertEqual(result.exitCode, 3)
    }

    /// Pause and Cancel stop DepotDownloader this way.
    func testAStoppedChildEndsTheRun() async throws {
        let stopper = ProcessStopper()
        async let result = ShellRunner.run(executable: "/bin/sleep", arguments: ["30"], environment: [:],
                                           stopper: stopper, terminal: true) { _ in }
        try await Task.sleep(for: .milliseconds(200))
        stopper.stop()
        let ended = try await result
        XCTAssertNotEqual(ended.exitCode, 0)
    }

    /// "é" is two bytes; a read can end between them.
    func testACharacterSplitAcrossReadsWaitsForItsRest() {
        let name = Array("Pokémon".utf8)
        let split = name.firstIndex(of: 0xC3)! + 1
        XCTAssertEqual(PseudoTerminal.unfinishedCharacter(at: Array(name[..<split])), 1)
        XCTAssertEqual(PseudoTerminal.unfinishedCharacter(at: name), 0)
        XCTAssertEqual(PseudoTerminal.unfinishedCharacter(at: Array("ok".utf8)), 0)
        XCTAssertEqual(PseudoTerminal.unfinishedCharacter(at: Array(Array("🎮".utf8)[..<3])), 3)
        XCTAssertEqual(PseudoTerminal.unfinishedCharacter(at: []), 0)
    }
}
