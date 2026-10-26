import XCTest
@testable import lifelify

@MainActor
final class DiaryVisitTagNormalizerTests: XCTestCase {
    func testWhitespaceCaseAndDiacritics_preserveFirstSpellingAndOrder() {
        XCTAssertEqual(DiaryVisitTagNormalizer.normalize(["  Café\n", "CAFE", "\t", "散歩", " 散歩 ", "Work", "work"]),
                       ["Café", "散歩", "Work"])
        XCTAssertEqual(DiaryVisitTagNormalizer.key(for: " Café\n"), DiaryVisitTagNormalizer.key(for: "cafe"))
    }

    func testLimit_countsUniqueNonemptyTagsAndHandlesNonpositiveLimits() {
        let tags = ["a", "A", " "] + (1...10).map { "tag\($0)" }
        XCTAssertEqual(DiaryVisitTagNormalizer.normalize(tags), ["a"] + (1...7).map { "tag\($0)" })
        XCTAssertEqual(DiaryVisitTagNormalizer.normalize(tags, limit: 2), ["a", "tag1"])
        XCTAssertEqual(DiaryVisitTagNormalizer.normalize(tags, limit: 0), [])
        XCTAssertEqual(DiaryVisitTagNormalizer.normalize(tags, limit: -1), [])
    }

    func testDiaryNormalization_usesSameRulesAndRetainsUserText() {
        let location = DiaryLocation(name: "User's place", address: nil, latitude: 1, longitude: 2,
                                     mapItemURL: nil, visitTags: [" Café ", "cafe", "散歩"])
        let entry = DiaryEntry(date: Date(timeIntervalSince1970: 1_700_000_000), text: "ユーザーの日記",
                              mood: nil, conditionScore: nil, locations: [location])
        let normalized = AppDataStore.normalizeDiaryEntries([entry])[0]
        XCTAssertEqual(normalized.text, entry.text)
        XCTAssertEqual(normalized.locations[0].visitTags, DiaryVisitTagNormalizer.normalize(location.visitTags))
        XCTAssertNil(normalized.mood)
        XCTAssertNil(normalized.conditionScore)
    }
}
