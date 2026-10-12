import XCTest
@testable import lifelify

final class CalendarWeekStartTests: XCTestCase {
    func testMissingPreference_preservesSundayLayout() throws {
        try withDefaults { defaults, _ in
            let calendar = CalendarWeekStart.load(from: defaults).applying(to: makeCalendar())
            let month = ScheduleMonth(containing: date(2026, 2, 14, in: calendar), calendar: calendar)

            XCTAssertEqual(month.weekCount, 4)
            XCTAssertEqual(month.dates.first!, date(2026, 2, 1, in: calendar))
            XCTAssertEqual(month.dates.compactMap { $0 }.count, 28)
        }
    }

    func testInvalidStoredPreference_fallsBackToSundayLayout() throws {
        try withDefaults { defaults, _ in
            defaults.set(7, forKey: CalendarWeekStart.storageKey)
            let preference = CalendarWeekStart.load(from: defaults)
            let calendar = preference.applying(to: makeCalendar())
            let interval = try XCTUnwrap(calendar.dateInterval(
                of: .weekOfYear, for: date(2026, 1, 1, in: calendar)
            ))

            XCTAssertEqual(interval.start, date(2025, 12, 28, in: calendar))
            XCTAssertEqual(preference.weekdaySymbols(in: calendar).first,
                           calendar.shortStandaloneWeekdaySymbols[0])
        }
    }

    func testPersistedMondayPreference_reopensWithMatchingMonthAndHeadings() throws {
        try withDefaults { defaults, suite in
            defaults.set(CalendarWeekStart.monday.rawValue, forKey: CalendarWeekStart.storageKey)
            let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let preference = CalendarWeekStart.load(from: reopenedDefaults)
            let calendar = preference.applying(to: makeCalendar())
            let month = ScheduleMonth(containing: date(2026, 2, 14, in: calendar), calendar: calendar)

            XCTAssertEqual(month.weekCount, 5)
            XCTAssertTrue(month.dates.prefix(6).allSatisfy { $0 == nil })
            XCTAssertEqual(month.dates[6], date(2026, 2, 1, in: calendar))
            XCTAssertEqual(preference.weekdaySymbols(in: calendar)[6],
                           calendar.shortStandaloneWeekdaySymbols[0])
        }
    }

    func testApplyingPreference_preservesCalendarEnvironmentAndOriginalValue() {
        var original = makeCalendar(identifier: .buddhist, timeZone: "America/Los_Angeles", locale: "ko_KR")
        original.firstWeekday = 4
        original.minimumDaysInFirstWeek = 4

        for preference in CalendarWeekStart.allCases {
            let configured = preference.applying(to: original)

            XCTAssertEqual(configured.identifier, original.identifier)
            XCTAssertEqual(configured.timeZone, original.timeZone)
            XCTAssertEqual(configured.locale, original.locale)
            XCTAssertEqual(configured.minimumDaysInFirstWeek, original.minimumDaysInFirstWeek)
            XCTAssertEqual(original.firstWeekday, 4)
        }
    }

    func testWeekHeadings_matchEachDateAcrossYearBoundaryInEveryAppLocale() throws {
        for locale in ["ja_JP", "en_US", "ko_KR", "zh_Hans_CN", "zh_Hant_TW"] {
            for preference in CalendarWeekStart.allCases {
                let calendar = preference.applying(to: makeCalendar(locale: locale))
                let week = try XCTUnwrap(calendar.dateInterval(
                    of: .weekOfYear, for: date(2026, 1, 1, in: calendar)
                ))
                let expectedStart = preference == .sunday
                    ? date(2025, 12, 28, in: calendar)
                    : date(2025, 12, 29, in: calendar)
                let headings = preference.weekdaySymbols(in: calendar)
                let days = JournalViewModel.weekDates(containing: date(2026, 1, 1, in: calendar), calendar: calendar)

                XCTAssertEqual(week.start, expectedStart, locale)
                XCTAssertEqual(days.first, expectedStart, locale)
                XCTAssertEqual(headings.count, 7)
                for (offset, day) in days.enumerated() {
                    let weekday = calendar.component(.weekday, from: day)
                    XCTAssertEqual(headings[offset], calendar.shortStandaloneWeekdaySymbols[weekday - 1], locale)
                }
            }
        }
    }

    func testFebruaryStartingMonday_fitsFourWeeksOnlyWithMondayPreference() {
        let base = makeCalendar()
        let anchor = date(2021, 2, 14, in: base)
        let mondayMonth = ScheduleMonth(containing: anchor, calendar: CalendarWeekStart.monday.applying(to: base))
        let sundayMonth = ScheduleMonth(containing: anchor, calendar: CalendarWeekStart.sunday.applying(to: base))

        XCTAssertEqual(mondayMonth.weekCount, 4)
        XCTAssertTrue(mondayMonth.dates.allSatisfy { $0 != nil })
        XCTAssertEqual(mondayMonth.dates.first!, date(2021, 2, 1, in: base))
        XCTAssertEqual(mondayMonth.dates.last!, date(2021, 2, 28, in: base))
        XCTAssertEqual(sundayMonth.weekCount, 5)
        XCTAssertNil(sundayMonth.dates[0])
        XCTAssertEqual(sundayMonth.dates[1], date(2021, 2, 1, in: base))
    }

    func testDaylightSavingWeeks_keepSevenLocalDatesAndCoherentHeadings() throws {
        let base = makeCalendar(timeZone: "America/Los_Angeles")
        let transitions = [(month: 3, day: 8, hours: 167), (month: 11, day: 1, hours: 169)]

        for transition in transitions {
            for preference in CalendarWeekStart.allCases {
                let calendar = preference.applying(to: base)
                let target = date(2026, transition.month, transition.day, 12, in: calendar)
                let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: target))
                let days = JournalViewModel.weekDates(containing: target, calendar: calendar)
                let headings = preference.weekdaySymbols(in: calendar)

                XCTAssertEqual(week.duration, Double(transition.hours * 3_600), accuracy: 0.001)
                XCTAssertEqual(Set(days).count, 7)
                XCTAssertTrue(days.contains(calendar.startOfDay(for: target)))
                XCTAssertEqual(calendar.date(byAdding: .day, value: 7, to: week.start), week.end)
                for (offset, day) in days.enumerated() {
                    XCTAssertEqual(day, calendar.startOfDay(for: day))
                    let weekday = calendar.component(.weekday, from: day)
                    XCTAssertEqual(headings[offset], calendar.shortStandaloneWeekdaySymbols[weekday - 1])
                }
            }
        }
    }

    func testJournalMonthColumns_matchWidgetForEveryMonthAndPreference() {
        for preference in CalendarWeekStart.allCases {
            let calendar = preference.applying(to: makeCalendar())
            for monthNumber in 1...12 {
                let monthStart = date(2026, monthNumber, 1, in: calendar)
                let widgetMonth = ScheduleMonth(containing: monthStart, calendar: calendar)
                let leadingDays = JournalViewModel.leadingDays(for: monthStart, calendar: calendar)

                XCTAssertEqual(widgetMonth.dates.firstIndex(where: { $0 != nil }), leadingDays)
                XCTAssertEqual(widgetMonth.weekdayNumbers[leadingDays], calendar.component(.weekday, from: monthStart))
                let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart)!
                XCTAssertEqual(calendar.component(.weekday, from: gridStart), calendar.firstWeekday)
            }
        }
    }

    private func makeCalendar(
        identifier: Calendar.Identifier = .gregorian,
        timeZone: String = "Asia/Tokyo",
        locale: String = "en_US"
    ) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        in calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func withDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let suite = "CalendarWeekStartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, suite)
    }
}
