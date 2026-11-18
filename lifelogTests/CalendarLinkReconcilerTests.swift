import XCTest
@testable import lifelify

@MainActor
final class CalendarLinkReconcilerTests: XCTestCase {
    func testAllCalendarIdentifiersChange_preservesEachCategoryAndHiddenSelection() {
        let saved = [
            link("old-work", title: "職場", category: "仕事用"),
            link("old-home", title: "自宅", category: "家族"),
            link("old-birthday", title: "誕生日", category: nil)
        ]
        let calendars = [
            link("new-home", title: "自宅"),
            link("new-birthday", title: "誕生日"),
            link("new-work", title: "職場")
        ]

        let result = reconcile(calendars, links: saved)

        XCTAssertEqual(result.links.map(\.calendarIdentifier), ["new-home", "new-birthday", "new-work"])
        XCTAssertEqual(result.links.map(\.categoryId), ["家族", nil, "仕事用"])
        XCTAssertTrue(result.unavailableLinks.isEmpty)
    }

    func testEmptyInventoryThenCalendarsReturn_restoresArchivedSelections() {
        let saved = [link("work", title: "職場", category: "勤務"),
                     link("hidden", title: "記念日", category: nil)]

        let empty = reconcile([], links: saved)
        let restored = reconcile([link("work", title: "職場"), link("hidden", title: "記念日")],
                                 links: empty.links, unavailableLinks: empty.unavailableLinks)

        XCTAssertTrue(empty.links.isEmpty)
        XCTAssertEqual(empty.unavailableLinks, saved)
        XCTAssertEqual(restored.links.map(\.categoryId), ["勤務", nil])
        XCTAssertTrue(restored.unavailableLinks.isEmpty)
    }

    func testPartialInventoryThenChangedIdentifiersReturn_restoresOnlyMissingCalendars() {
        let saved = [link("work", title: "職場", category: "勤務"),
                     link("home", title: "自宅", category: "家族")]
        let partial = reconcile([link("work", title: "職場")], links: saved)

        let restored = reconcile([link("new-home", title: "自宅"), link("work", title: "職場")],
                                 links: partial.links, unavailableLinks: partial.unavailableLinks)

        XCTAssertEqual(partial.links.map(\.calendarIdentifier), ["work"])
        XCTAssertEqual(partial.unavailableLinks.map(\.calendarIdentifier), ["home"])
        XCTAssertEqual(restored.links.map(\.calendarIdentifier), ["work", "new-home"])
        XCTAssertEqual(restored.links.map(\.categoryId), ["勤務", "家族"])
        XCTAssertTrue(restored.unavailableLinks.isEmpty)
    }

    func testSameTitleInDifferentAccounts_recoversUsingSourceIdentity() {
        let saved = [
            link("old-a", title: "Calendar", category: "会社", sourceIdentifier: "account-a", sourceTitle: "A"),
            link("old-b", title: "Calendar", category: "家族", sourceIdentifier: "account-b", sourceTitle: "B")
        ]
        let calendars = [
            link("new-b", title: "Calendar", sourceIdentifier: "account-b", sourceTitle: "B"),
            link("new-a", title: "Calendar", sourceIdentifier: "account-a", sourceTitle: "A")
        ]

        let result = reconcile(calendars, links: saved)

        XCTAssertEqual(result.links.map(\.categoryId), ["家族", "会社"])
        XCTAssertTrue(result.unavailableLinks.isEmpty)
    }

    func testSameTitleInUnrelatedAccount_doesNotMoveSavedCategory() {
        let saved = link("old", title: "Calendar", category: "会社", sourceIdentifier: "a", sourceTitle: "A")
        let calendar = link("new", title: "Calendar", sourceIdentifier: "b", sourceTitle: "B")

        let result = reconcile([calendar], links: [saved])

        XCTAssertEqual(result.links.first?.categoryId, "ご飯")
        XCTAssertEqual(result.unavailableLinks, [saved])
    }

    func testIdenticalCalendarAndAccountTitlesWithStableSourceIdentifiers_recoversEachAccountSelection() {
        let saved = [
            link("old-a", title: "Calendar", category: "会社", sourceIdentifier: "account-a", sourceTitle: "Gmail"),
            link("old-b", title: "Calendar", category: "家族", sourceIdentifier: "account-b", sourceTitle: "Gmail")
        ]
        let calendars = [
            link("new-b", title: "Calendar", sourceIdentifier: "account-b", sourceTitle: "Gmail"),
            link("new-a", title: "Calendar", sourceIdentifier: "account-a", sourceTitle: "Gmail")
        ]

        let result = reconcile(calendars, links: saved)

        XCTAssertEqual(result.links.map(\.categoryId), ["家族", "会社"])
        XCTAssertTrue(result.unavailableLinks.isEmpty)
    }

    func testSavedAccountStillPresentUnderAnotherCalendar_doesNotTransferChoiceToSameNameAccount() {
        let saved = [
            link("old-a", title: "Calendar", category: "会社", sourceIdentifier: "account-a", sourceTitle: "Gmail"),
            link("remaining-a", title: "Other calendar", category: "休日", sourceIdentifier: "account-a", sourceTitle: "Gmail")
        ]
        let calendars = [
            link("remaining-a", title: "Other calendar", sourceIdentifier: "account-a", sourceTitle: "Gmail"),
            link("new-b", title: "Calendar", sourceIdentifier: "account-b", sourceTitle: "Gmail")
        ]

        let result = reconcile(calendars, links: saved)

        XCTAssertEqual(result.links.map(\.categoryId), ["休日", "ご飯"])
        XCTAssertEqual(result.unavailableLinks.map(\.calendarIdentifier), ["old-a"])
    }

    func testCurrentAccountKnownUnderAnotherSavedCalendar_doesNotInheritDisappearedAccountsHiddenSelection() {
        let saved = [
            link("old-a", title: "Calendar", category: nil, sourceIdentifier: "account-a", sourceTitle: "Gmail"),
            link("old-b", title: "Work", category: "勤務", sourceIdentifier: "account-b", sourceTitle: "Gmail")
        ]
        let calendar = link("new-b", title: "Calendar", sourceIdentifier: "account-b", sourceTitle: "Gmail")

        let result = reconcile([calendar], links: saved)

        XCTAssertEqual(result.links.first?.categoryId, "ご飯")
        XCTAssertEqual(result.unavailableLinks, saved)
    }

    func testKnownSavedAccountWithMissingCurrentSource_doesNotMoveSavedCategory() {
        let saved = link("old", title: "Calendar", category: "会社", sourceIdentifier: "a", sourceTitle: "A")

        let result = reconcile([link("new", title: "Calendar")], links: [saved])

        XCTAssertEqual(result.links.first?.categoryId, "ご飯")
        XCTAssertEqual(result.unavailableLinks, [saved])
    }

    func testCalendarAndSourceIdentifiersChange_recoversUsingSourceTitleAndType() {
        let saved = link("old", title: "予定", category: "仕事", sourceIdentifier: "old-account", sourceTitle: "Account")
        let calendar = link("new", title: "予定", sourceIdentifier: "new-account", sourceTitle: "Account")

        let result = reconcile([calendar], links: [saved])

        XCTAssertEqual(result.links.first?.categoryId, "仕事")
        XCTAssertEqual(result.links.first?.sourceIdentifier, "new-account")
        XCTAssertTrue(result.unavailableLinks.isEmpty)
    }

    func testSameAccountNameWithDifferentSourceTypes_doesNotRecover() {
        let saved = link("old", title: "予定", category: "仕事", sourceIdentifier: "old-account",
                         sourceTitle: "Account", sourceType: 1)
        let calendar = link("new", title: "予定", sourceIdentifier: "new-account",
                            sourceTitle: "Account", sourceType: 2)

        let result = reconcile([calendar], links: [saved])

        XCTAssertEqual(result.links.first?.categoryId, "ご飯")
        XCTAssertEqual(result.unavailableLinks, [saved])
    }

    func testSameCalendarTitleWithDifferentCalendarTypes_doesNotRecover() {
        let saved = link("old", title: "予定", category: "仕事", calendarType: 1)
        let calendar = link("new", title: "予定", calendarType: 2)

        let result = reconcile([calendar], links: [saved])

        XCTAssertEqual(result.links.first?.categoryId, "ご飯")
        XCTAssertEqual(result.unavailableLinks, [saved])
    }

    func testExactIdentifierWithRenamedCalendarAndAccount_preservesSelectionAndRefreshesMetadata() {
        let saved = link("same", title: "Old calendar", category: nil, sourceIdentifier: "old-account",
                         sourceTitle: "Old account", color: "#111111")
        let calendar = link("same", title: "New calendar", sourceIdentifier: "new-account",
                            sourceTitle: "New account", color: "#222222")

        let result = reconcile([calendar], links: [saved])

        XCTAssertEqual(result.links, [calendar])
        XCTAssertNil(result.links.first?.categoryId)
        XCTAssertTrue(result.unavailableLinks.isEmpty)
    }

    func testUniqueLegacyTitle_recoversIntoNewSourceMetadata() {
        let saved = link("old", title: "職場", category: "勤務")
        let calendar = link("new", title: "職場", sourceIdentifier: "account", sourceTitle: "Work")

        let result = reconcile([calendar], links: [saved])

        XCTAssertEqual(result.links.first?.categoryId, "勤務")
        XCTAssertEqual(result.links.first?.sourceIdentifier, "account")
        XCTAssertTrue(result.unavailableLinks.isEmpty)
    }

    func testLegacyDuplicateTitlesIncludingExactMatch_doesNotStealOtherSelection() {
        let saved = [link("same", title: "Calendar", category: "会社"),
                     link("old", title: "Calendar", category: "家族")]
        let calendars = [link("same", title: "Calendar"), link("new", title: "Calendar")]

        let result = reconcile(calendars, links: saved)

        XCTAssertEqual(result.links.map(\.categoryId), ["会社", "ご飯"])
        XCTAssertEqual(result.unavailableLinks.map(\.calendarIdentifier), ["old"])
    }

    func testOneLegacySelectionAndMultipleCurrentTitles_doesNotReuseSelection() {
        let saved = link("old", title: "Calendar", category: "会社")

        let result = reconcile([link("first", title: "Calendar"), link("second", title: "Calendar")],
                               links: [saved])

        XCTAssertEqual(result.links.map(\.categoryId), ["ご飯", "ご飯"])
        XCTAssertEqual(result.unavailableLinks, [saved])
    }

    func testSameSourceAndTitleWithMultipleSavedCandidates_doesNotGuess() {
        let saved = [
            link("old-a", title: "Calendar", category: "会社", sourceIdentifier: "account", sourceTitle: "A"),
            link("old-b", title: "Calendar", category: "家族", sourceIdentifier: "account", sourceTitle: "A")
        ]
        let calendar = link("new", title: "Calendar", sourceIdentifier: "account", sourceTitle: "A")

        let result = reconcile([calendar], links: saved)

        XCTAssertEqual(result.links.first?.categoryId, "ご飯")
        XCTAssertEqual(result.unavailableLinks, saved)
    }

    func testExistingOrderDuplicatesAndArchive_preferActiveSelectionAndAppendReturningCalendars() {
        let first = link("first", title: "First", category: "一番")
        let second = link("second", title: "Second", category: "二番")
        let returning = link("returning", title: "Returning", category: "復帰")
        let removed = link("removed", title: "Removed", category: "保存")
        let result = reconcile(
            [link("returning", title: "Returning"), link("second", title: "Second"),
             link("first", title: "First"), link("first", title: "Duplicate inventory")],
            links: [first, second, link("first", title: "Duplicate active", category: "不採用")],
            unavailableLinks: [link("first", title: "Duplicate archive", category: "不採用"), returning, removed, removed]
        )

        XCTAssertEqual(result.links.map(\.calendarIdentifier), ["first", "second", "returning"])
        XCTAssertEqual(result.links.map(\.categoryId), ["一番", "二番", "復帰"])
        XCTAssertEqual(result.unavailableLinks, [removed])
    }

    func testNewCalendar_usesDefaultClosureWhileSavedHiddenCalendarStaysHidden() {
        var requestedTitles: [String] = []
        let result = CalendarLinkReconciler.reconcile(
            calendars: [link("saved", title: "Hidden"), link("new", title: "Holidays")],
            links: [link("saved", title: "Hidden", category: nil)],
            unavailableLinks: [],
            defaultCategory: { title in
                requestedTitles.append(title)
                return nil
            }
        )

        XCTAssertEqual(requestedTitles, ["Holidays"])
        XCTAssertEqual(result.links.map(\.categoryId), [nil, nil])
    }

    func testLegacyEncodedLink_decodesWithoutSourceMetadata() throws {
        let json = Data(##"{"calendarIdentifier":"old","calendarTitle":"職場","categoryId":"勤務","colorHex":"#123456"}"##.utf8)

        let saved = try JSONDecoder().decode(CalendarCategoryLink.self, from: json)

        XCTAssertEqual(saved.categoryId, "勤務")
        XCTAssertNil(saved.sourceIdentifier)
        XCTAssertNil(saved.sourceTitle)
        XCTAssertNil(saved.sourceTypeRawValue)
        XCTAssertNil(saved.calendarTypeRawValue)
    }

    private func reconcile(
        _ calendars: [CalendarCategoryLink],
        links: [CalendarCategoryLink],
        unavailableLinks: [CalendarCategoryLink] = []
    ) -> CalendarLinkReconciler.Result {
        CalendarLinkReconciler.reconcile(calendars: calendars, links: links,
                                         unavailableLinks: unavailableLinks, defaultCategory: { _ in "ご飯" })
    }

    private func link(
        _ identifier: String,
        title: String,
        category: String? = nil,
        sourceIdentifier: String? = nil,
        sourceTitle: String? = nil,
        sourceType: Int? = nil,
        calendarType: Int? = nil,
        color: String? = nil
    ) -> CalendarCategoryLink {
        CalendarCategoryLink(
            calendarIdentifier: identifier, calendarTitle: title, categoryId: category, colorHex: color,
            sourceIdentifier: sourceIdentifier, sourceTitle: sourceTitle,
            sourceTypeRawValue: sourceType ?? (sourceIdentifier == nil && sourceTitle == nil ? nil : 1),
            calendarTypeRawValue: calendarType
        )
    }
}
