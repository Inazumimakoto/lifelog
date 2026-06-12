//
//  StoredRawValueTests.swift
//  lifelogTests
//

import XCTest
@testable import lifelify

/// 永続化された enum の raw value を固定するテスト。
/// これらの値は SwiftData / Firestore に保存済みデータとして存在するため、
/// 変更すると既存ユーザーのデータが壊れる(または fallback 値に化ける)。
/// このテストが落ちたら、変更をやめるかマイグレーションを書くこと。
final class StoredRawValueTests: XCTestCase {

    func testTaskPriorityRawValues() {
        XCTAssertEqual(TaskPriority.high.rawValue, 3)
        XCTAssertEqual(TaskPriority.medium.rawValue, 2)
        XCTAssertEqual(TaskPriority.low.rawValue, 1)
    }

    func testMoodLevelRawValues() {
        XCTAssertEqual(MoodLevel.veryLow.rawValue, 1)
        XCTAssertEqual(MoodLevel.low.rawValue, 2)
        XCTAssertEqual(MoodLevel.neutral.rawValue, 3)
        XCTAssertEqual(MoodLevel.high.rawValue, 4)
        XCTAssertEqual(MoodLevel.veryHigh.rawValue, 5)
    }

    func testAnniversaryTypeRawValues() {
        XCTAssertEqual(AnniversaryType.countdown.rawValue, "countdown")
        XCTAssertEqual(AnniversaryType.since.rawValue, "since")
    }

    func testLetterStatusRawValues() {
        // 封印済み手紙の状態が draft に化ける事故を防ぐ
        XCTAssertEqual(LetterStatus.draft.rawValue, "draft")
        XCTAssertEqual(LetterStatus.sealed.rawValue, "sealed")
        XCTAssertEqual(LetterStatus.deliverable.rawValue, "deliverable")
        XCTAssertEqual(LetterStatus.opened.rawValue, "opened")
    }

    func testHabitScheduleStorageLiteralsRoundtrip() {
        // "daily" / "weekdays" / "custom" のリテラルは
        // SwiftDataModels.swift と ModelMapping.swift の2箇所に重複定義
        // されている。往復で同一性を確認することで両者のズレを検出する。
        let daily = Habit(title: "毎日", iconName: "star", colorHex: "#FF0000", schedule: .daily)
        let weekdays = Habit(title: "平日", iconName: "star", colorHex: "#FF0000", schedule: .weekdays)
        let custom = Habit(title: "カスタム", iconName: "star", colorHex: "#FF0000",
                           schedule: .custom(days: [.monday, .friday]))

        for habit in [daily, weekdays, custom] {
            let restored = Habit(sd: SDHabit(domain: habit))
            XCTAssertEqual(restored.schedule, habit.schedule,
                           "HabitSchedule の保存リテラルが往復で壊れている: \(habit.title)")
        }
    }
}
