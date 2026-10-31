import XCTest
@testable import Keyring

/// Jobs "every 12 months" are Gregorian months. A phone set to Saudi Arabia counts in Islamic months of 29.5 days.
final class MonthIntervalTests: XCTestCase {
    func testAYearIsAYearOnAPhoneWhoseCalendarCountsLunarMonths() throws {
        let saudi = Locale(identifier: "en_SA").calendar
        try XCTSkipIf(saudi.identifier == .gregorian, "this runtime has no non-Gregorian calendar for the region")
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = saudi.timeZone
        let last = try XCTUnwrap(gregorian.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 12)))
        let now = try XCTUnwrap(gregorian.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let value = DueInput(intervalDistance: 0, intervalMonths: 12, lastDate: last, lastReading: nil, currentReading: 0, dailyUse: 0, meter: .hours)
        let result = DueEngine.evaluate(value, now: now, calendar: saudi)
        XCTAssertEqual(result.dueDate, gregorian.date(from: DateComponents(year: 2027, month: 1, day: 10, hour: 12)))
    }

    func testCalendarMonthsEndOnTheLastDayOfAGregorianMonth() throws {
        let saudi = Locale(identifier: "en_SA").calendar
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = saudi.timeZone
        let signed = try XCTUnwrap(gregorian.date(from: DateComponents(year: 2026, month: 3, day: 3)))
        let now = try XCTUnwrap(gregorian.date(from: DateComponents(year: 2027, month: 3, day: 20)))
        let value = DueInput(intervalDistance: 0, intervalMonths: 12, lastDate: signed, lastReading: nil, currentReading: 0, dailyUse: 0, meter: .hours, calendarMonths: true)
        let due = try XCTUnwrap(DueEngine.evaluate(value, now: now, calendar: saudi).dueDate)
        let parts = gregorian.dateComponents([.year, .month, .day], from: due)
        XCTAssertEqual([parts.year, parts.month, parts.day], [2027, 3, 31])
    }
}
