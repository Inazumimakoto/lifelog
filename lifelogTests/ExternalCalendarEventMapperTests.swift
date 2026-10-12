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
}
