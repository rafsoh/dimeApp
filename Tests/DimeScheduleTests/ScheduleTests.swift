@testable import DimeSchedule
import XCTest

final class RecurrenceRuleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testDailyWeeklyMonthly() {
        let start = date(2026, 1, 10)
        XCTAssertEqual(RecurrenceRule.nextDate(after: start, type: 1, coefficient: 3, calendar: calendar), date(2026, 1, 13))
        XCTAssertEqual(RecurrenceRule.nextDate(after: start, type: 2, coefficient: 2, calendar: calendar), date(2026, 1, 24))
        XCTAssertEqual(RecurrenceRule.nextDate(after: start, type: 3, coefficient: 1, calendar: calendar), date(2026, 2, 10))
    }

    func testMonthlyFromEndOfMonthClampsToShorterMonth() {
        XCTAssertEqual(RecurrenceRule.nextDate(after: date(2026, 1, 31), type: 3, coefficient: 1, calendar: calendar), date(2026, 2, 28))
    }

    func testInvalidRulesReturnNilInsteadOfCrashingOrLooping() {
        let start = date(2026, 1, 10)
        XCTAssertNil(RecurrenceRule.nextDate(after: start, type: 1, coefficient: 0, calendar: calendar))
        XCTAssertNil(RecurrenceRule.nextDate(after: start, type: 2, coefficient: -1, calendar: calendar))
        XCTAssertNil(RecurrenceRule.nextDate(after: start, type: 0, coefficient: 1, calendar: calendar))
        XCTAssertNil(RecurrenceRule.nextDate(after: start, type: 7, coefficient: 1, calendar: calendar))
    }
}

final class BudgetPeriodTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testPeriodEnds() {
        let start = date(2026, 3, 1)
        XCTAssertEqual(BudgetPeriod.end(of: start, type: 1, calendar: calendar), date(2026, 3, 2))
        XCTAssertEqual(BudgetPeriod.end(of: start, type: 2, calendar: calendar), date(2026, 3, 8))
        XCTAssertEqual(BudgetPeriod.end(of: start, type: 3, calendar: calendar), date(2026, 4, 1))
        XCTAssertEqual(BudgetPeriod.end(of: start, type: 4, calendar: calendar), date(2027, 3, 1))
        XCTAssertNil(BudgetPeriod.end(of: start, type: 0, calendar: calendar))
    }

    func testCurrentStartRollsForwardWholePeriods() {
        let start = date(2026, 3, 1)
        let now = date(2026, 3, 25)
        XCTAssertEqual(BudgetPeriod.currentStart(from: start, type: 2, now: now, calendar: calendar), date(2026, 3, 22))
        XCTAssertEqual(BudgetPeriod.currentStart(from: start, type: 3, now: now, calendar: calendar), start)
    }

    func testPeriodEndingExactlyNowStartsTheNextOne() {
        let start = date(2026, 3, 1)
        XCTAssertEqual(BudgetPeriod.currentStart(from: start, type: 1, now: date(2026, 3, 2), calendar: calendar), date(2026, 3, 2))
    }

    func testUnknownTypeAndFutureStartAreLeftAlone() {
        let start = date(2026, 3, 1)
        XCTAssertEqual(BudgetPeriod.currentStart(from: start, type: 0, now: date(2030, 1, 1), calendar: calendar), start)
        XCTAssertEqual(BudgetPeriod.currentStart(from: start, type: 2, now: date(2026, 2, 1), calendar: calendar), start)
    }

    func testVeryOldStartTerminates() {
        let start = date(1800, 1, 1)
        let result = BudgetPeriod.currentStart(from: start, type: 1, now: date(2026, 1, 1), calendar: calendar)
        XCTAssertLessThanOrEqual(result, date(2026, 1, 1))
        XCTAssertGreaterThan(result, start)
    }
}
