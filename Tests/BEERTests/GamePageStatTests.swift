import XCTest
@testable import BEER

final class GamePageStatTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    // MARK: - Play time

    func testPlaytimeFormats() {
        XCTAssertEqual(PlaytimeFormat.decimalHours.text(minutes: 2_604), "43.4 hours")
        XCTAssertEqual(PlaytimeFormat.hoursAndMinutes.text(minutes: 2_604), "43h 24m")
        XCTAssertEqual(PlaytimeFormat.wholeHours.text(minutes: 2_604), "43 hours")
    }

    func testPlaytimeUnderAnHourAndOnTheHour() {
        XCTAssertEqual(PlaytimeFormat.decimalHours.text(minutes: 1), "1 minute")
        XCTAssertEqual(PlaytimeFormat.wholeHours.text(minutes: 45), "45 minutes")
        XCTAssertEqual(PlaytimeFormat.hoursAndMinutes.text(minutes: 45), "45m")
        XCTAssertEqual(PlaytimeFormat.hoursAndMinutes.text(minutes: 120), "2h")
        XCTAssertEqual(PlaytimeFormat.wholeHours.text(minutes: 89), "1 hour")
    }

    // MARK: - Last played

    func testRelativeLastPlayed() {
        let now = day(22, hour: 9)
        func text(_ date: Date) -> String { LastPlayedFormat.relative.text(date, now: now, calendar: calendar) }
        XCTAssertEqual(text(day(22, hour: 1)), "Today")
        XCTAssertEqual(text(day(21, hour: 23)), "Yesterday")
        XCTAssertEqual(text(day(19)), "3 days ago")
        XCTAssertEqual(text(day(10)), day(10).formatted(date: .abbreviated, time: .omitted),
                       "a week or more back shows the date")
    }

    func testDateLastPlayedIsAlwaysTheDate() {
        XCTAssertEqual(LastPlayedFormat.date.text(day(22), now: day(22), calendar: calendar),
                       day(22).formatted(date: .abbreviated, time: .omitted))
    }

    // MARK: - Which stats show

    func testStoredStatsRoundTripAndSkipUnknownNames() {
        let stats: Set<GamePageStat> = [.size, .appID]
        XCTAssertEqual(GamePageStat.encode(stats), "appID,size")
        XCTAssertEqual(GamePageStat.decode("appID,size"), stats)
        XCTAssertEqual(GamePageStat.decode("achievements,playtime"), [.playtime])
        XCTAssertEqual(GamePageStat.decode(""), [])
    }

    func testStatsFollowTheFixedOrderAndFormats() {
        let game = SteamLibraryGame(appID: 250900, name: "Isaac", lastPlayed: day(22), playtimeMinutes: 75)
        let stats = GamePageStat.stats(Set(GamePageStat.allCases), for: game, installedBytes: 654_270_000,
                                       playtime: .hoursAndMinutes, lastPlayed: .relative, now: day(22))
        XCTAssertEqual(stats.map(\.title), ["APP ID", "LAST PLAYED", "PLAY TIME", "SIZE ON DISK"])
        XCTAssertEqual(stats[1].value, "Today")
        XCTAssertEqual(stats[1].inline, "Last played Today")
        XCTAssertEqual(stats[2].value, "1h 15m")
    }

    func testStatsWithoutAValueAreLeftOut() {
        let unplayed = SteamLibraryGame(appID: 10, name: "New")
        let stats = GamePageStat.stats([.lastPlayed, .playtime, .size], for: unplayed, installedBytes: nil,
                                       playtime: .decimalHours, lastPlayed: .date)
        XCTAssertEqual(stats.map(\.value), ["Never"], "no play time to show, size not measured yet")
    }

    func testNonSteamGameIsNotCalledNeverPlayed() {
        let mine = SteamLibraryGame(appID: -1, name: "Mine", isNonSteam: true)
        let stats = GamePageStat.stats([.appID, .lastPlayed], for: mine, installedBytes: nil,
                                       playtime: .decimalHours, lastPlayed: .date)
        XCTAssertEqual(stats.map(\.value), ["Non-Steam"])
    }

    func testDefaultsMatchTheOriginalPage() {
        XCTAssertEqual(GamePageStat.defaultShown, [.appID, .playtime])
    }
}
