//
//  ReviewMapPresentationTests.swift
//  lifelogTests
//

import XCTest
import MapKit
import CoreGraphics
@testable import lifelify

/// docs/requirements.md §4.4.2: visit counts stay per day and date summaries
/// retain their existing truncation while map markers change presentation.
@MainActor
final class ReviewMapPresentationTests: XCTestCase {
    func testDifferentPlacesAtSameCoordinates_keepSeparateGroupKeys() {
        let cafe = location(name: "カフェ", mapItemURL: nil)
        let bookstore = location(name: "本屋", mapItemURL: nil)

        XCTAssertNotEqual(ReviewLocationGroupBuilder.makeKey(for: cafe),
                          ReviewLocationGroupBuilder.makeKey(for: bookstore))
    }

    func testSamePlaceWithWhitespaceAndCaseVariants_keepsSameGroupKey() {
        let cafe = location(name: "Cafe", mapItemURL: nil)
        let sameCafe = location(name: "  CAFE \n", mapItemURL: nil)

        XCTAssertEqual(ReviewLocationGroupBuilder.makeKey(for: cafe),
                       ReviewLocationGroupBuilder.makeKey(for: sameCafe))
    }

    func testMultipleRecordsOnSameDay_countAsOneVisitAndMergeTags() {
        let morning = date(month: 10, day: 6, hour: 9)
        var builder = ReviewLocationGroupBuilder(location: location(), date: morning,
                                                 photoPaths: ["morning.jpg"], tags: ["カフェ"])
        builder.add(date: date(month: 10, day: 6, hour: 18),
                    photoPaths: ["morning.jpg", "evening.jpg"], tags: ["カフェ", "仕事"])
        builder.add(date: date(month: 10, day: 5), photoPaths: [], tags: ["カフェ"])

        let group = ReviewLocationGroup(id: builder.id, location: builder.location, visits: builder.visits)

        XCTAssertEqual(group.count, 2)
        XCTAssertEqual(group.latestDate, morning.startOfDay)
        XCTAssertEqual(group.visits.first?.photoPaths, ["morning.jpg", "evening.jpg"])
        XCTAssertEqual(group.visits.first?.tags, ["カフェ", "仕事"])
    }

    func testSameMonthSummary_showsLatestThreeDatesAndRemainingCount() {
        let dates = [6, 5, 4, 3, 2].map { date(month: 10, day: $0) }

        XCTAssertEqual(ReviewDateFormatter.summary(for: dates), "\(monthDay(dates[0])),5,4+2")
    }

    func testDifferentMonthSummary_showsLatestTwoDatesAndRemainingCount() {
        let dates = [date(month: 10, day: 6), date(month: 9, day: 30), date(month: 9, day: 20)]

        XCTAssertEqual(ReviewDateFormatter.summary(for: dates),
                       "\(monthDay(dates[0])),\(monthDay(dates[1]))+1")
    }

    func testVisitFrequency_markerSizeRemainsWithinSubtleThreeSteps() {
        XCTAssertEqual(ReviewMapPresentation.markerDiameter(for: 1, expanded: false), 6)
        XCTAssertEqual(ReviewMapPresentation.markerDiameter(for: 2, expanded: false), 7)
        XCTAssertEqual(ReviewMapPresentation.markerDiameter(for: 4, expanded: false), 7)
        XCTAssertEqual(ReviewMapPresentation.markerDiameter(for: 5, expanded: false), 8)
        XCTAssertEqual(ReviewMapPresentation.markerDiameter(for: 10_000, expanded: false), 8)
    }

    func testMostFrequentTag_determinesCompactMarkerColor() {
        let definitions = tags(["カフェ", "仕事", "買い物"])
        let group = group(tagsByVisit: [["仕事", "カフェ"], ["カフェ"], ["買い物"]])

        XCTAssertEqual(ReviewMapPresentation.dominantTagName(for: group, definitions: definitions,
                                                            selectedFilters: []), "カフェ")
    }

    func testRepeatedTagVariants_countOncePerVisitForDominantColor() {
        let definitions = tags(["Work", "Cafe"])
        let group = group(tagsByVisit: [["Cafe", " cafe ", "CAFÉ", "Work"], ["Work"]])

        XCTAssertEqual(ReviewMapPresentation.dominantTagName(for: group, definitions: definitions,
                                                            selectedFilters: []), "Work")
        XCTAssertEqual(ReviewMapPresentation.tagNames(for: group, definitions: definitions,
                                                      selectedFilters: []).count, 2)
    }

    func testNineColorLimit_selectsMostFrequentTagsInFixedOrder() {
        let names = (0..<12).map { "タグ\($0)" }
        let definitions = tags(names)
        let visits = names.enumerated().flatMap { index, name in
            Array(repeating: [name], count: index + 1)
        }
        let group = group(tagsByVisit: visits)

        let selected = ReviewMapPresentation.tagNames(for: group, definitions: definitions,
                                                       selectedFilters: [])

        XCTAssertEqual(selected, Array(names.suffix(9)))
        // Frequencies choose the colors; tag order fixes their positions in the circle.
        XCTAssertEqual(ReviewMapPresentation.tagNames(for: group, definitions: Array(definitions.reversed()),
                                                       selectedFilters: []), selected)
    }

    func testSingleTagFilter_markerOnlyUsesSelectedTag() {
        let definitions = tags(["カフェ", "仕事"])
        let group = group(tagsByVisit: [["カフェ", "仕事"], ["カフェ"], ["カフェ"]])

        XCTAssertEqual(ReviewMapPresentation.tagNames(for: group, definitions: definitions,
                                                      selectedFilters: ["仕事"]), ["仕事"])
        XCTAssertEqual(ReviewMapPresentation.dominantTagName(for: group, definitions: definitions,
                                                            selectedFilters: ["仕事"]), "仕事")
    }

    func testUntaggedVisits_haveNoTagColors() {
        let group = group(tagsByVisit: [[], []])

        XCTAssertEqual(ReviewMapPresentation.tagNames(for: group, definitions: tags(["カフェ"]),
                                                      selectedFilters: []), [])
        XCTAssertNil(ReviewMapPresentation.dominantTagName(for: group, definitions: tags(["カフェ"]),
                                                          selectedFilters: []))
    }

    func testOverlappingLabels_selectedPlaceTakesPriorityOverNewerPlace() {
        let frame = CGRect(x: 20, y: 20, width: 80, height: 20)
        let candidates = [
            candidate("latest", frame: frame, day: 6),
            candidate("selected", frame: frame.offsetBy(dx: 10, dy: 0), day: 5, selected: true),
            candidate("separate", frame: frame.offsetBy(dx: 150, dy: 0), day: 4)
        ]

        XCTAssertEqual(ReviewMapLabelLayout.visibleIDs(for: candidates, in: mapBounds),
                       Set(["selected", "separate"]))
    }

    func testOverlappingLabels_latestPlaceTakesPriorityRegardlessOfInputOrder() {
        let frame = CGRect(x: 20, y: 20, width: 80, height: 20)
        let candidates = [candidate("older", frame: frame, day: 5),
                          candidate("latest", frame: frame.offsetBy(dx: 10, dy: 0), day: 6)]

        XCTAssertEqual(ReviewMapLabelLayout.visibleIDs(for: candidates, in: mapBounds), Set(["latest"]))
        XCTAssertEqual(ReviewMapLabelLayout.visibleIDs(for: Array(candidates.reversed()), in: mapBounds),
                       Set(["latest"]))
    }

    func testTagFiltering_recalculatesVisitsAndCountFromMatchingDays() throws {
        let source = group(tagsByVisit: [["カフェ", "仕事"], ["カフェ"], ["仕事"]])

        let filtered = try XCTUnwrap(ReviewMapPresentation.filteredGroups([source],
                                                                          selectedFilters: ["仕事"]).first)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered.uniqueDates, [source.visits[0].date, source.visits[2].date])
        XCTAssertEqual(ReviewMapPresentation.markerDiameter(for: filtered.count, expanded: false), 7)
        XCTAssertEqual(ReviewMapPresentation.tagNames(for: filtered, definitions: tags(["カフェ", "仕事"]),
                                                      selectedFilters: ["仕事"]), ["仕事"])
    }

    func testUntaggedAndTagFilters_combineWithOR() throws {
        let source = group(tagsByVisit: [["仕事"], [], ["カフェ"], ["カフェ", "仕事"]])

        let filtered = try XCTUnwrap(ReviewMapPresentation.filteredGroups([source],
                                                       selectedFilters: ["カフェ", "__untagged__"]).first)

        XCTAssertEqual(filtered.count, 3)
        XCTAssertEqual(filtered.uniqueDates, Array(source.uniqueDates.dropFirst()))
    }

    func testNoMatchingTag_removesGroupFromMap() {
        XCTAssertTrue(ReviewMapPresentation.filteredGroups([group(tagsByVisit: [["カフェ"]])],
                                                           selectedFilters: ["仕事"]).isEmpty)
    }

    func testZoomTransitions_keepCompactAndExpandedStatesWithinHysteresis() {
        let compact = ReviewMapPresentation.updateZoomState(distance: 8_000, wasExpanded: false,
                                                            wereDatesVisible: false)
        let expanded = ReviewMapPresentation.updateZoomState(distance: 8_000, wasExpanded: true,
                                                             wereDatesVisible: false)
        let zoomIn = ReviewMapPresentation.updateZoomState(distance: 6_000, wasExpanded: false,
                                                           wereDatesVisible: false)
        let zoomOut = ReviewMapPresentation.updateZoomState(distance: 10_000, wasExpanded: true,
                                                            wereDatesVisible: true)

        XCTAssertFalse(compact.expanded)
        XCTAssertTrue(expanded.expanded)
        XCTAssertTrue(zoomIn.expanded)
        XCTAssertFalse(zoomOut.expanded)
        XCTAssertFalse(zoomOut.datesVisible)
    }

    func testDateZoomThreshold_retainsLabelStateWhileZoomChangesSlightly() {
        let previouslyHidden = ReviewMapPresentation.updateZoomState(distance: 2_800, wasExpanded: true,
                                                                     wereDatesVisible: false)
        let previouslyShown = ReviewMapPresentation.updateZoomState(distance: 2_800, wasExpanded: true,
                                                                    wereDatesVisible: true)
        let zoomIn = ReviewMapPresentation.updateZoomState(distance: 2_000, wasExpanded: true,
                                                           wereDatesVisible: false)
        let zoomOut = ReviewMapPresentation.updateZoomState(distance: 3_500, wasExpanded: true,
                                                            wereDatesVisible: true)

        XCTAssertFalse(previouslyHidden.datesVisible)
        XCTAssertTrue(previouslyShown.datesVisible)
        XCTAssertTrue(zoomIn.datesVisible)
        XCTAssertFalse(zoomOut.datesVisible)
    }

    func testLabelsOutsideMapOrUnderControls_areHidden() {
        let controlFrame = CGRect(x: 200, y: 10, width: 80, height: 40)
        let candidates = [
            candidate("outside", frame: CGRect(x: -5, y: 20, width: 80, height: 20), day: 6),
            candidate("control", frame: controlFrame, day: 5),
            candidate("visible", frame: CGRect(x: 20, y: 80, width: 80, height: 20), day: 4)
        ]

        XCTAssertEqual(ReviewMapLabelLayout.visibleIDs(for: candidates, in: mapBounds,
                                                      avoiding: [controlFrame]), Set(["visible"]))
    }

    private let mapBounds = CGRect(x: 0, y: 0, width: 300, height: 200)

    private func candidate(_ id: String, frame: CGRect, day: Int,
                           selected: Bool = false) -> ReviewMapLabelCandidate {
        ReviewMapLabelCandidate(id: id, frame: frame, latestDate: date(month: 10, day: day),
                                isSelected: selected)
    }

    private func tags(_ names: [String]) -> [LocationVisitTagDefinition] {
        names.enumerated().map { LocationVisitTagDefinition(name: $0.element, sortOrder: $0.offset) }
    }

    private func group(tagsByVisit: [[String]]) -> ReviewLocationGroup {
        let visits = tagsByVisit.enumerated().map { index, tags in
            ReviewLocationVisit(date: date(month: 10, day: 6).addingTimeInterval(-Double(index) * 86_400),
                                photoPaths: [], tags: tags)
        }
        return ReviewLocationGroup(id: "cafe", location: location(), visits: visits)
    }

    private func date(month: Int, day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private func location(name: String = "カフェ",
                          mapItemURL: String? = "https://maps.apple.com/?q=cafe") -> DiaryLocation {
        DiaryLocation(name: name, address: nil, latitude: 35.65, longitude: 139.70,
                      mapItemURL: mapItemURL)
    }
}
