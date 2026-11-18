import XCTest
@testable import lifelify

@MainActor
final class ExternalCalendarEventMapperTests: XCTestCase {
    func testCategoryMapping_preservesLinkedUserCategoryHidesDisabledAndDefaultsUnknown() {
        let mapper = ExternalCalendarEventMapper(links: [
            CalendarCategoryLink(calendarIdentifier: "work", calendarTitle: "Work",
                                 categoryId: "私のカテゴリ", colorHex: nil),
            CalendarCategoryLink(calendarIdentifier: "hidden", calendarTitle: "Hidden",
                                 categoryId: nil, colorHex: "#ffffff")
        ])

        XCTAssertEqual(mapper.categoryName(for: "work"), "私のカテゴリ")
        XCTAssertNil(mapper.categoryName(for: "hidden"))
        XCTAssertEqual(mapper.categoryName(for: "new-calendar"), CategoryPalette.defaultCategoryName)
    }

    func testExplicitEmptyCategory_isNotTreatedAsHidden() {
        let mapper = ExternalCalendarEventMapper(links: [
            CalendarCategoryLink(calendarIdentifier: "empty", calendarTitle: "Empty",
                                 categoryId: "", colorHex: nil)
        ])

        XCTAssertEqual(mapper.categoryName(for: "empty"), "")
        XCTAssertTrue(mapper.map([]).isEmpty)
    }

    func testUnavailableCalendarEvents_keepSavedCategoryAndHiddenSettingWhileCurrentChoiceWins() {
        let mapper = ExternalCalendarEventMapper(links: [
            CalendarCategoryLink(calendarIdentifier: "current", calendarTitle: "Current",
                                 categoryId: "Updated choice", colorHex: nil)
        ], unavailableLinks: [
            CalendarCategoryLink(calendarIdentifier: "missing", calendarTitle: "Missing",
                                 categoryId: "Saved choice", colorHex: nil),
            CalendarCategoryLink(calendarIdentifier: "hidden", calendarTitle: "Hidden",
                                 categoryId: nil, colorHex: nil),
            CalendarCategoryLink(calendarIdentifier: "current", calendarTitle: "Old snapshot",
                                 categoryId: "Old choice", colorHex: nil)
        ])

        XCTAssertEqual(mapper.categoryName(for: "missing"), "Saved choice")
        XCTAssertNil(mapper.categoryName(for: "hidden"))
        XCTAssertEqual(mapper.categoryName(for: "current"), "Updated choice")
    }
}
