//
//  LocationVisitTagDefinitionTests.swift
//  lifelogTests
//

import XCTest
@testable import lifelify

@MainActor
final class LocationVisitTagDefinitionTests: XCTestCase {
    func testAutomaticColor_usesLeastUsedPaletteColorRegardlessOfTagOrder() {
        let palette = LocationVisitTagPalette.hexColors
        let leastUsed = palette[4]
        let existing = palette + palette.filter { $0 != leastUsed }

        XCTAssertEqual(LocationVisitTagPalette.automaticHex(existingHexes: existing), leastUsed)
        XCTAssertEqual(LocationVisitTagPalette.automaticHex(existingHexes: Array(existing.reversed())),
                       leastUsed)
        XCTAssertEqual(LocationVisitTagPalette.automaticHex(existingHexes: []), palette[0])
    }

    func testLegacyJSONWithoutColor_decodesWithAutomaticColor() throws {
        let id = UUID(uuidString: "477E2ED5-C184-4237-9D16-7792972BF2EE")!
        let legacy = Data("""
        {"id":"\(id.uuidString)","name":"カフェ","sortOrder":2,"createdAt":0}
        """.utf8)

        let tag = try JSONDecoder().decode(LocationVisitTagDefinition.self, from: legacy)

        XCTAssertEqual(tag.id, id)
        XCTAssertEqual(tag.name, "カフェ")
        XCTAssertEqual(tag.colorHex, LocationVisitTagPalette.defaultHex(for: 2))
    }

    func testLegacyInvalidColor_decodesWithAutomaticColor() throws {
        let legacy = Data("""
        {"id":"477E2ED5-C184-4237-9D16-7792972BF2EE","name":"仕事","sortOrder":4,"createdAt":0,"colorHex":"invalid"}
        """.utf8)

        let tag = try JSONDecoder().decode(LocationVisitTagDefinition.self, from: legacy)

        XCTAssertEqual(tag.colorHex, LocationVisitTagPalette.defaultHex(for: 4))
    }

    func testCustomColor_roundtripPreservesCanonicalColor() throws {
        let tag = LocationVisitTagDefinition(name: "カフェ", sortOrder: 0, colorHex: "#f97316")

        let encoded = try JSONEncoder().encode(tag)
        let restored = try JSONDecoder().decode(LocationVisitTagDefinition.self, from: encoded)

        XCTAssertEqual(restored, tag)
        XCTAssertEqual(restored.colorHex, "F97316")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(fields["colorHex"] as? String, "F97316")
    }

    func testRenameAndReorder_roundtripKeepsAssignedColor() throws {
        var tag = LocationVisitTagDefinition(name: "カフェ", sortOrder: 1)
        let assignedColor = tag.colorHex

        tag.name = "喫茶店"
        tag.sortOrder = 7
        let restored = try JSONDecoder().decode(LocationVisitTagDefinition.self,
                                                from: JSONEncoder().encode(tag))

        XCTAssertEqual(restored.name, "喫茶店")
        XCTAssertEqual(restored.sortOrder, 7)
        XCTAssertEqual(restored.colorHex, assignedColor)
    }
}
