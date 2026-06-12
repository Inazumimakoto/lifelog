//
//  AppDataStore+SampleData.swift
//  lifelog
//

import Foundation

extension AppDataStore {

    // MARK: - Sample Data (DEBUG only)

    #if DEBUG
    func seedJapaneseScheduleForScreenshotsIfNeeded() {
        let arguments = Set(ProcessInfo.processInfo.arguments)
        guard Self.screenshotsModeLaunchArguments.isDisjoint(with: arguments) == false else { return }

        let minimumEventCountForScreenshots = 18
        guard calendarEvents.count < minimumEventCountForScreenshots else { return }

        var mergedEvents = calendarEvents
        let seededEvents = makeJapaneseSampleScheduleEvents(referenceDate: Date())
        for event in seededEvents where containsSimilarCalendarEvent(event, in: mergedEvents) == false {
            mergedEvents.append(event)
        }

        guard mergedEvents.count != calendarEvents.count else { return }
        mergedEvents.sort {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }
            return $0.startDate < $1.startDate
        }
        calendarEvents = mergedEvents
        eventsCache.removeAll()
        persistCalendarEvents()
    }

    private func makeJapaneseSampleScheduleEvents(referenceDate: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }

        func timed(_ title: String, _ dayOffset: Int, _ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int, _ calendarName: String) -> CalendarEvent {
            let targetDay = day(dayOffset)
            let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: targetDay) ?? targetDay
            let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: targetDay) ?? start.addingTimeInterval(3_600)
            return CalendarEvent(
                title: title,
                startDate: start,
                endDate: end,
                calendarName: calendarName
            )
        }

        func allDay(_ title: String, _ dayOffset: Int, _ lengthDays: Int, _ calendarName: String) -> CalendarEvent {
            let start = day(dayOffset)
            let end = calendar.date(byAdding: .day, value: max(1, lengthDays), to: start) ?? start.addingTimeInterval(86_400)
            return CalendarEvent(
                title: title,
                startDate: start,
                endDate: end,
                calendarName: calendarName,
                isAllDay: true
            )
        }

        return [
            timed("朝の散歩", -2, 7, 0, 7, 30, "健康"),
            timed("チーム朝会", -1, 9, 30, 10, 0, "仕事"),
            timed("週次ふりかえり", -1, 18, 30, 19, 15, "仕事"),
            timed("チーム朝会", 0, 9, 30, 10, 0, "仕事"),
            timed("仕様確認ミーティング", 0, 11, 0, 12, 0, "仕事"),
            timed("ランチ（中華）", 0, 12, 30, 13, 20, "プライベート"),
            timed("E2EE手紙の下書き", 0, 21, 0, 21, 30, "タイムカプセル"),
            timed("ジム", 1, 19, 0, 20, 0, "健康"),
            timed("買い物", 2, 18, 30, 19, 30, "プライベート"),
            allDay("日帰り旅行", 3, 1, "旅行"),
            timed("カレンダー整理", 4, 20, 30, 21, 0, "プライベート"),
            timed("チーム朝会", 5, 9, 30, 10, 0, "仕事"),
            timed("デザインレビュー", 5, 15, 0, 16, 0, "仕事"),
            timed("歯科検診", 7, 10, 30, 11, 15, "健康"),
            timed("習慣チェック", 8, 21, 0, 21, 20, "習慣"),
            allDay("出張（大阪）", 10, 2, "仕事"),
            timed("メモ整理", 13, 20, 0, 20, 40, "学習"),
            timed("写真整理", 15, 21, 0, 21, 40, "プライベート"),
            timed("タイムカプセル作成", 18, 20, 0, 21, 0, "タイムカプセル"),
            timed("読書", 21, 22, 0, 22, 40, "学習"),
            timed("チーム朝会", 22, 9, 30, 10, 0, "仕事"),
            timed("美容院", 25, 14, 0, 15, 0, "プライベート"),
            allDay("実家へ帰省", 29, 2, "家族"),
            timed("翌月の計画づくり", 34, 20, 0, 21, 0, "プライベート"),
            timed("月次レビュー", 40, 18, 0, 19, 0, "仕事"),
            timed("振り返りと日記", 44, 21, 0, 21, 40, "習慣")
        ]
    }

    private func containsSimilarCalendarEvent(_ candidate: CalendarEvent, in events: [CalendarEvent]) -> Bool {
        events.contains {
            $0.title == candidate.title &&
            $0.calendarName == candidate.calendarName &&
            abs($0.startDate.timeIntervalSince(candidate.startDate)) < 1 &&
            abs($0.endDate.timeIntervalSince(candidate.endDate)) < 1 &&
            $0.isAllDay == candidate.isAllDay
        }
    }

    func seedSampleDataIfNeeded() {
        guard tasks.isEmpty && diaryEntries.isEmpty && habits.isEmpty && anniversaries.isEmpty && calendarEvents.isEmpty else { return }
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart)
        tasks = [
            Task(title: "Morning workout",
                 detail: "20 min yoga",
                 startDate: todayStart,
                 endDate: todayStart,
                 priority: .medium),
            Task(title: "Design review",
                 detail: "Bujo dashboard layout",
                 startDate: todayStart,
                 endDate: todayStart,
                 priority: .high),
            Task(title: "Buy groceries",
                 startDate: tomorrow,
                 endDate: calendar.date(byAdding: .day, value: 2, to: tomorrow) ?? tomorrow,
                 priority: .low)
        ]

        let sampleNotes = [
            "ランニングで気分がすっきり。ミーティングも穏やかに進んだ。",
            "睡眠不足で少しぼんやり。夜は早めに休む予定。",
            "在宅で集中できた。コードレビューも褒められた。",
            "移動が多くて歩き疲れたけれど、夕方のコーヒーで復活。",
            "週末モードでのんびり。散歩して深呼吸。",
            "雨で外に出られず、ストレッチだけ。少し肩が重い。",
            "たっぷり寝たのでエネルギー満タン。新しいアイデアが浮かんだ。"
        ]
        diaryEntries = (0..<7).compactMap { offset -> DiaryEntry? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else {
                return nil
            }
            let moodLevel: MoodLevel = {
                switch offset {
                case 0: return .veryHigh
                case 1: return .high
                case 2: return .neutral
                case 3: return .low
                case 4: return .neutral
                case 5: return .veryLow
                default: return .high
                }
            }()
            let condition = max(1, min(5, 5 - offset + Int.random(in: -1...1)))
            return DiaryEntry(date: date,
                              text: sampleNotes[min(offset, sampleNotes.count - 1)],
                              mood: moodLevel,
                              conditionScore: condition,
                              locationName: "自宅",
                              latitude: 35.68,
                              longitude: 139.76)
        }

        let habit1 = Habit(title: "Meditation", iconName: "brain.head.profile", colorHex: "#F97316", schedule: .daily)
        let habit2 = Habit(title: "Drink Water", iconName: "drop.fill", colorHex: "#0EA5E9", schedule: .custom(days: [.monday, .wednesday, .friday]))
        let habit3 = Habit(title: "Read 20 pages", iconName: "book.fill", colorHex: "#22C55E", schedule: .weekdays)
        habits = [habit1, habit2, habit3]

        habitRecords = [
            HabitRecord(habitID: habit1.id, date: now, isCompleted: true),
            HabitRecord(habitID: habit3.id, date: now, isCompleted: false)
        ]

        anniversaries = [
            Anniversary(title: "Next vacation", targetDate: calendar.date(byAdding: .day, value: 45, to: now) ?? now, type: .countdown, repeatsYearly: false),
            Anniversary(title: "Started Bullet Journal", targetDate: calendar.date(byAdding: .year, value: -2, to: now) ?? now, type: .since, repeatsYearly: true)
        ]

        calendarEvents = [
            CalendarEvent(title: "Team stand-up", startDate: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now) ?? now,
                          endDate: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now, calendarName: "Work"),
            CalendarEvent(title: "Lunch with Sara", startDate: calendar.date(bySettingHour: 12, minute: 30, second: 0, of: now) ?? now,
                          endDate: calendar.date(bySettingHour: 13, minute: 30, second: 0, of: now) ?? now, calendarName: "Personal"),
            CalendarEvent(title: "Offsite", startDate: todayStart,
                          endDate: calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400),
                          calendarName: "Work",
                          isAllDay: true),
            CalendarEvent(title: "Yoga class", startDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(18_000) ?? now,
                          endDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(19_800) ?? now, calendarName: "Wellness")
        ]
        persistCalendarEvents()
    }
    #endif

}
