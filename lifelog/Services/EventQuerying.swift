//
//  EventQuerying.swift
//  lifelog
//
//  アプリ本体とウィジェット拡張(LifelogWidgetsExtension)の両方に
//  コンパイルされる共有ファイル。
//
//  「内部イベント + UserDefaults(JSON)由来の外部イベントをマージし、
//   id で重複排除(開始が後のものを採用)、開始日時→タイトルで整列する」
//  というロジックが AppDataStore / WallpaperCalendarDataProvider /
//  ScheduleWidget の3箇所に重複し、整列のタイブレークが食い違って
//  いた。ここを唯一の正(single source of truth)とする。
//

import Foundation

enum EventQuerying {

    // MARK: - UserDefaults Keys

    // これまで3ファイルに文字列リテラルで手書き重複していたキー。
    // 保存済みデータとウィジェットが依存するため文字列値は不変。
    static let externalCalendarEventsDefaultsKey = "ExternalCalendarEvents_Storage_V1"
    static let externalCalendarRangeDefaultsKey = "ExternalCalendarRange_Storage_V1"

    // MARK: - External Events Decode

    /// 共有 UserDefaults(App Group)から外部カレンダーイベントの
    /// JSON を読み出して [CalendarEvent] へデコードする純粋ロジック。
    /// データ無し・デコード失敗時は空配列を返す(呼び出し側は従来どおり
    /// 何も表示しない)。
    static func loadExternalEvents(
        from defaults: UserDefaults?
    ) -> [CalendarEvent] {
        let store = defaults ?? .standard
        guard let data = store.data(forKey: externalCalendarEventsDefaultsKey),
              let events = try? JSONDecoder().decode([CalendarEvent].self, from: data)
        else {
            return []
        }
        return events
    }

    // MARK: - Day-Window Filter

    /// [rangeStart, rangeEndExclusive) と重なるイベントだけを残す半開区間フィルタ。
    /// Source-zone all-day labels are projected into the display calendar;
    /// timed events retain their original instants.
    static func overlapping(
        _ events: [CalendarEvent],
        rangeStart: Date,
        rangeEndExclusive: Date,
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        events.filter { overlaps($0, rangeStart: rangeStart, rangeEndExclusive: rangeEndExclusive, calendar: calendar) }
    }

    static func overlaps(_ event: CalendarEvent, rangeStart: Date, rangeEndExclusive: Date, calendar: Calendar = .current) -> Bool {
        event.displayStartDate(calendar: calendar) < rangeEndExclusive && event.displayEndDate(calendar: calendar) > rangeStart
    }

    /// Stored source midnight can be up to 26 hours from its display midnight.
    /// Broaden SQL's coarse filter, then apply `overlapping` to the resulting rows.
    static func storageRange(rangeStart: Date, rangeEndExclusive: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -2, to: rangeStart) ?? rangeStart.addingTimeInterval(-172_800)
        let end = calendar.date(byAdding: .day, value: 2, to: rangeEndExclusive) ?? rangeEndExclusive.addingTimeInterval(172_800)
        return DateInterval(start: start, end: end)
    }

    // MARK: - Sort Policy

    /// 整列方針: 開始日時の昇順、同時刻はタイトルの昇順。
    /// AppDataStore.events(on:) は従来 startDate のみで整列しており
    /// 同時刻時の順序が非決定的だった。ウィジェット側の決定的な
    /// タイトル・タイブレークへ統一する。
    static func sortByStartThenTitle(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        let lhsDate = lhs.displayStartDate(), rhsDate = rhs.displayStartDate()
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.title < rhs.title
    }

    // MARK: - Merge / Dedup / Sort

    /// 内部イベントと外部イベントをマージし、id で重複排除して整列する。
    /// 重複排除の方針(AppDataStore 由来の正): 同一 id が衝突したら
    /// 「開始日時が後のもの」を採用する。整列は開始→タイトル。
    static func mergedDedupedSorted(
        internalEvents: [CalendarEvent],
        externalEvents: [CalendarEvent]
    ) -> [CalendarEvent] {
        (internalEvents + externalEvents)
            .reduce(into: [UUID: CalendarEvent]()) { result, event in
                if let existing = result[event.id] {
                    // 開始が後(より新しい)方を残す。
                    result[event.id] = existing.startDate >= event.startDate ? existing : event
                } else {
                    result[event.id] = event
                }
            }
            .values
            .sorted(by: sortByStartThenTitle)
    }
}
