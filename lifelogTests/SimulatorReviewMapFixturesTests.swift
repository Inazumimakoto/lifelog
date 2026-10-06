//
//  SimulatorReviewMapFixturesTests.swift
//  lifelogTests
//

#if DEBUG && targetEnvironment(simulator)
import XCTest
@testable import lifelify

/// Exercise only the pure generator, without loading a store or saving diary data.
@MainActor
final class SimulatorReviewMapFixturesTests: XCTestCase {
    func testSameReferenceDate_producesIdenticalEntriesAndIDs() {
        let first = SimulatorReviewMapFixtures.entries(referenceDate: referenceDate, calendar: calendar)
        let second = SimulatorReviewMapFixtures.entries(referenceDate: referenceDate, calendar: calendar)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testDemoLocations_produceOneThousandDistinctMapGroups() {
        let groups = groupedLocations()

        XCTAssertEqual(groups.count, 1_000)
        XCTAssertEqual(Set(groups.map(\.id)).count, 1_000)
    }

    func testDemoVisits_coverAllThreeMarkerFrequencySteps() {
        XCTAssertEqual(Set(groupedLocations().map(\.count)), Set([1, 3, 6]))
    }

    func testDemoCoordinates_coverJapanFromHokkaidoToOkinawa() throws {
        let locations = entries.flatMap(\.locations)
        let latitudes = locations.map(\.latitude)
        let longitudes = locations.map(\.longitude)

        XCTAssertGreaterThan(try XCTUnwrap(latitudes.max()), 43)
        XCTAssertLessThan(try XCTUnwrap(latitudes.min()), 27)
        XCTAssertGreaterThan(try XCTUnwrap(longitudes.max()), 140)
        XCTAssertLessThan(try XCTUnwrap(longitudes.min()), 128)
        XCTAssertTrue(latitudes.allSatisfy { (20...46).contains($0) })
        XCTAssertTrue(longitudes.allSatisfy { (122...154).contains($0) })
    }

    func testMultidayTags_includeNineColorExampleWithinPerVisitLimit() {
        let groups = groupedLocations()

        XCTAssertTrue(groups.contains { $0.allTags.count >= 9 })
        XCTAssertTrue(entries.flatMap(\.locations).allSatisfy { $0.visitTags.count <= 8 })
    }

    func testDemoDates_neverExceedReferenceDate() {
        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.allSatisfy { $0.date <= referenceDate })
        XCTAssertTrue(groupedLocations().flatMap(\.visits).allSatisfy { $0.date <= referenceDate })
    }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12))!
    }

    private var entries: [DiaryEntry] {
        SimulatorReviewMapFixtures.entries(referenceDate: referenceDate, calendar: calendar)
    }

    private func groupedLocations() -> [ReviewLocationGroup] {
        var builders: [String: ReviewLocationGroupBuilder] = [:]
        for entry in entries {
            for location in entry.locations {
                let key = ReviewLocationGroupBuilder.makeKey(for: location)
                if var builder = builders[key] {
                    builder.add(date: entry.date, photoPaths: location.photoPaths, tags: location.visitTags)
                    builders[key] = builder
                } else {
                    builders[key] = ReviewLocationGroupBuilder(location: location, date: entry.date,
                                                               photoPaths: location.photoPaths,
                                                               tags: location.visitTags)
                }
            }
        }
        return builders.values.map {
            ReviewLocationGroup(id: $0.id, location: $0.location, visits: $0.visits)
        }
    }
}
#endif
