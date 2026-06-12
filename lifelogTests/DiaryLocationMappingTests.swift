//
//  DiaryLocationMappingTests.swift
//  lifelogTests
//

import XCTest
@testable import lifelify

/// DiaryEntry ⇄ SDDiaryEntry の位置情報マッピングのテスト。
/// 位置情報は SDDiaryEntry.locationsData(JSON blob)とレガシー列
/// (locationName/latitude/longitude)の二重保存になっており、
/// デコード失敗時はレガシー列にフォールバックする仕様。
/// この往復が壊れると訪問タグ・複数地点が黙って消えるため固定する。
final class DiaryLocationMappingTests: XCTestCase {

    func testLocationsSurviveRoundtripWithVisitTags() {
        let locations = [
            DiaryLocation(name: "渋谷カフェ",
                          address: "東京都渋谷区1-2-3",
                          latitude: 35.6595,
                          longitude: 139.7005,
                          mapItemURL: "https://maps.apple.com/?q=test",
                          photoPaths: ["photos/a.jpg"],
                          visitTags: ["カフェ", "作業"]),
            DiaryLocation(name: "代々木公園",
                          address: nil,
                          latitude: 35.6712,
                          longitude: 139.6949,
                          mapItemURL: nil,
                          visitTags: ["散歩"])
        ]
        let entry = DiaryEntry(date: Date(timeIntervalSince1970: 1_700_000_000),
                               text: "テスト日記",
                               mood: .high,
                               conditionScore: 4,
                               locations: locations)

        let sd = SDDiaryEntry(domain: entry)
        let restored = DiaryEntry(sd: sd)

        XCTAssertEqual(restored.locations.count, 2)
        XCTAssertEqual(restored.locations[0].name, "渋谷カフェ")
        XCTAssertEqual(restored.locations[0].visitTags, ["カフェ", "作業"])
        XCTAssertEqual(restored.locations[0].address, "東京都渋谷区1-2-3")
        XCTAssertEqual(restored.locations[1].visitTags, ["散歩"])
        XCTAssertEqual(restored.text, entry.text)
        XCTAssertEqual(restored.mood, .high)
    }

    /// locationsData が無い古いレコードはレガシー列から単一地点を復元する
    func testLegacyColumnsFallbackWhenBlobMissing() {
        let entry = DiaryEntry(date: Date(timeIntervalSince1970: 1_600_000_000),
                               text: "古い日記",
                               locationName: "旧形式の場所",
                               latitude: 34.0,
                               longitude: 135.0)
        let sd = SDDiaryEntry(domain: entry)
        // 旧バージョンで保存されたレコードを再現: JSON blob を欠落させる
        sd.locationsData = nil

        let restored = DiaryEntry(sd: sd)

        XCTAssertEqual(restored.locations.count, 1)
        XCTAssertEqual(restored.locations.first?.name, "旧形式の場所")
        XCTAssertEqual(restored.locations.first?.latitude, 34.0)
    }
}
