import XCTest
@testable import BEER

/// When a log panel keeps its newest line in view. Distances are how far the
/// end of the log is below what the panel shows.
@MainActor
final class LogFollowTests: XCTestCase {
    func testFollowsFromTheStart() {
        let follow = LogFollow()
        XCTAssertTrue(follow.isFollowing)
        XCTAssertTrue(follow.contentGrew(), "new lines scroll into view")
    }

    func testScrollingUpStopsFollowing() {
        let follow = LogFollow()
        follow.scrolled(distanceFromEnd: 300)
        XCTAssertFalse(follow.isFollowing)
        XCTAssertFalse(follow.contentGrew(), "new lines leave the panel where the player put it")
    }

    func testScrollingBackToTheEndFollowsAgain() {
        let follow = LogFollow()
        follow.scrolled(distanceFromEnd: 300)
        // A few points short of the end still counts.
        follow.scrolled(distanceFromEnd: 8)
        XCTAssertTrue(follow.isFollowing)
        XCTAssertTrue(follow.contentGrew())
    }

    /// Past the end, as the scroll bounces back.
    func testOverscrollingTheEndFollows() {
        let follow = LogFollow()
        follow.scrolled(distanceFromEnd: 300)
        follow.scrolled(distanceFromEnd: -20)
        XCTAssertTrue(follow.isFollowing)
    }

    /// The panel moving between new lines arriving and it scrolling to them
    /// isn't the player scrolling up.
    func testMovementWhileCatchingUpIsIgnored() {
        let follow = LogFollow()
        XCTAssertTrue(follow.contentGrew())
        follow.scrolled(distanceFromEnd: 40)
        XCTAssertTrue(follow.isFollowing)
        follow.caughtUp()
        follow.scrolled(distanceFromEnd: 0)
        XCTAssertTrue(follow.isFollowing)
    }

    func testScrollingUpAfterCatchingUpStillCounts() {
        let follow = LogFollow()
        _ = follow.contentGrew()
        follow.caughtUp()
        follow.scrolled(distanceFromEnd: 300)
        XCTAssertFalse(follow.isFollowing)
    }
}
