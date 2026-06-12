//
//  EventQueryingTests.swift
//  lifelogTests
//

import XCTest
@testable import lifelify

/// 共有 EventQuerying のマージ・重複排除・整列・期間フィルタを固定する。
/// この方針はアプリ本体(events(on:))・壁紙カレンダー・ウィジェットの
/// 3箇所で共有されるため、退行すると見える順序や重複が静かに壊れる。
final class EventQueryingTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
        comps.timeZone = .current
        return calendar.date(from: comps) ?? Date()
    }

    private func event(id: UUID = UUID(),
                       title: String,
                       start: Date,
                       end: Date,
                       isAllDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: title, startDate: start, endDate: end,
                      calendarName: "仕事", isAllDay: isAllDay)
    }

    // MARK: - Dedup

    func testDedupKeepsLaterStart() {
        let id = UUID()
        let earlier = event(id: id, title: "古い", start: date(2026, 6, 1, 9), end: date(2026, 6, 1, 10))
        let later = event(id: id, title: "新しい", start: date(2026, 6, 1, 11), end: date(2026, 6, 1, 12))

        // 内部に古い、外部に新しい(開始が後)を入れる。
        let result = EventQuerying.mergedDedupedSorted(internalEvents: [earlier], externalEvents: [later])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "新しい")
        XCTAssertEqual(result.first?.startDate, date(2026, 6, 1, 11))
    }

    func testDedupKeepsLaterStartRegardlessOfOrder() {
        // 引数順を入れ替えても「開始が後」を採用する。
        let id = UUID()
        let earlier = event(id: id, title: "古い", start: date(2026, 6, 1, 9), end: date(2026, 6, 1, 10))
        let later = event(id: id, title: "新しい", start: date(2026, 6, 1, 11), end: date(2026, 6, 1, 12))
        let result = EventQuerying.mergedDedupedSorted(internalEvents: [later], externalEvents: [earlier])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "新しい")
    }

    // MARK: - Sort

    func testSortByStartThenTitle() {
        let a = event(title: "A会議", start: date(2026, 6, 1, 9), end: date(2026, 6, 1, 10))
        let b = event(title: "B会議", start: date(2026, 6, 1, 9), end: date(2026, 6, 1, 10))
        let c = event(title: "早い", start: date(2026, 6, 1, 8), end: date(2026, 6, 1, 9))

        // 同時刻(9時)は A→B のタイトル昇順、8時開始が先頭。
        let result = EventQuerying.mergedDedupedSorted(internalEvents: [b, a], externalEvents: [c])
        XCTAssertEqual(result.map(\.title), ["早い", "A会議", "B会議"])
    }

    // MARK: - Day-Window Filter

    func testOverlappingHalfOpenWindowBoundaries() {
        let dayStart = date(2026, 6, 10, 0)
        let dayEnd = date(2026, 6, 11, 0)

        // 前日に終わる: 当日終了境界(endDate == dayStart)は重ならない(end > start 判定)。
        let endsAtBoundary = event(title: "前日終わり", start: date(2026, 6, 9, 23), end: dayStart)
        // 翌日開始境界(startDate == dayEnd)は含まれない(start < end 判定)。
        let startsAtBoundary = event(title: "翌日始まり", start: dayEnd, end: date(2026, 6, 11, 1))
        // 当日内。
        let inside = event(title: "当日", start: date(2026, 6, 10, 9), end: date(2026, 6, 10, 10))
        // 日をまたぐ(前日開始・当日終了)。
        let spanning = event(title: "跨ぎ", start: date(2026, 6, 9, 23), end: date(2026, 6, 10, 1))

        let result = EventQuerying.overlapping(
            [endsAtBoundary, startsAtBoundary, inside, spanning],
            rangeStart: dayStart,
            rangeEndExclusive: dayEnd
        )
        let titles = Set(result.map(\.title))
        XCTAssertTrue(titles.contains("当日"))
        XCTAssertTrue(titles.contains("跨ぎ"))
        XCTAssertFalse(titles.contains("前日終わり"))
        XCTAssertFalse(titles.contains("翌日始まり"))
    }

    func testOverlappingIncludesAllDayEvent() {
        let dayStart = date(2026, 6, 10, 0)
        let dayEnd = date(2026, 6, 11, 0)
        // 終日イベント(0:00〜翌0:00)も重なりとして含まれる。
        let allDay = event(title: "終日", start: dayStart, end: dayEnd, isAllDay: true)
        let result = EventQuerying.overlapping([allDay], rangeStart: dayStart, rangeEndExclusive: dayEnd)
        XCTAssertEqual(result.map(\.title), ["終日"])
    }

    // MARK: - External Events Decode

    func testLoadExternalEventsRoundTrip() {
        let suite = "EventQueryingTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("テスト用 UserDefaults を作成できない")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let events = [event(title: "外部", start: date(2026, 6, 1, 9), end: date(2026, 6, 1, 10))]
        let data = try? JSONEncoder().encode(events)
        defaults.set(data, forKey: EventQuerying.externalCalendarEventsDefaultsKey)

        let loaded = EventQuerying.loadExternalEvents(from: defaults)
        XCTAssertEqual(loaded.map(\.title), ["外部"])
    }

    func testLoadExternalEventsEmptyWhenNoData() {
        let suite = "EventQueryingTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("テスト用 UserDefaults を作成できない")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(EventQuerying.loadExternalEvents(from: defaults).isEmpty)
    }

    func testDefaultsKeyStringIsStable() {
        // 保存済みデータ・ウィジェットが依存するため文字列値は不変。
        XCTAssertEqual(EventQuerying.externalCalendarEventsDefaultsKey, "ExternalCalendarEvents_Storage_V1")
        XCTAssertEqual(EventQuerying.externalCalendarRangeDefaultsKey, "ExternalCalendarRange_Storage_V1")
    }
}
