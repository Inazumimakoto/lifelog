import Foundation
import SwiftData
import WidgetKit
import os

#if DEBUG && targetEnvironment(simulator)
extension AppDataStore {
    /// Local demo fixtures only (docs/requirements.md §4.11); never compiled into a physical-device build.
    func seedSimulatorDemoDataIfNeeded() {
        guard PersistenceController.isSimulatorDemoMode else { return }
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)!
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let seededDayKey = "simulatorDemo.seededDay.v1"
        guard (defaults.object(forKey: seededDayKey) as? Date) != today else { return }

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today)!
        }
        func identifier(_ index: Int) -> UUID {
            UUID(uuidString: String(format: "DE000000-0000-4000-8000-%012d", index))!
        }
        func event(_ index: Int, _ title: String, offset: Int, hour: Int, category: String) -> CalendarEvent {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day(offset))!
            return CalendarEvent(
                id: identifier(index), title: title, startDate: start,
                endDate: calendar.date(byAdding: .hour, value: 1, to: start)!,
                calendarName: category
            )
        }

        var demoEvents = [
            event(1, String(localized: "チーム朝会"), offset: 0, hour: 10, category: "仕事"),
            event(2, String(localized: "買い物"), offset: 0, hour: 17, category: "趣味")
        ]
        for (index, offset) in [-4, -2, 2, 4, 5, 7, 10, 12, 15, 18, 21, 24].enumerated() {
            demoEvents.append(event(
                index + 10,
                index.isMultiple(of: 2) ? String(localized: "デザインレビュー") : String(localized: "ジム"),
                offset: offset,
                hour: index.isMultiple(of: 2) ? 14 : 19,
                category: index.isMultiple(of: 2) ? "仕事" : "趣味"
            ))
        }
        demoEvents.append(CalendarEvent(
            id: identifier(30), title: String(localized: "日帰り旅行"),
            startDate: day(9), endDate: day(10), calendarName: "旅行", isAllDay: true
        ))
        let demoTasks = [
            Task(id: identifier(101), title: String(localized: "Design review"), startDate: today, endDate: today, priority: .high),
            Task(id: identifier(102), title: String(localized: "読書"), startDate: today, endDate: today, priority: .medium),
            Task(id: identifier(103), title: String(localized: "Buy groceries"), startDate: day(1), endDate: day(1), priority: .low),
            Task(id: identifier(104), title: String(localized: "写真整理"), startDate: day(3), endDate: day(3), priority: .medium)
        ]

        do {
            let savedEvents = try modelContext.fetch(FetchDescriptor<SDCalendarEvent>())
            let savedTasks = try modelContext.fetch(FetchDescriptor<SDTask>())
            for event in demoEvents {
                if let existing = savedEvents.first(where: { $0.id == event.id }) {
                    existing.update(from: event)
                } else {
                    modelContext.insert(SDCalendarEvent(domain: event))
                }
            }
            for task in demoTasks {
                if let existing = savedTasks.first(where: { $0.id == task.id }) {
                    existing.update(from: task)
                } else {
                    modelContext.insert(SDTask(domain: task))
                }
            }
            try modelContext.save()
            calendarEvents = try modelContext.fetch(FetchDescriptor<SDCalendarEvent>()).map { CalendarEvent(sd: $0) }
            tasks = try modelContext.fetch(FetchDescriptor<SDTask>()).map { Task(sd: $0) }
            eventsCache.removeAll()
            // The demo widget shares only this suite. Remove any old screenshot calendar cache.
            defaults.removeObject(forKey: Self.externalCalendarEventsDefaultsKey)
            defaults.removeObject(forKey: Self.externalCalendarRangeDefaultsKey)
            defaults.set(today, forKey: seededDayKey)
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        } catch {
            modelContext.rollback()
            AppLogger.data.error("Simulator demo data could not be saved: \(error)")
        }
    }
}
#endif
