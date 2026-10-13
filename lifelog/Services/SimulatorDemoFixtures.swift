import Foundation

#if DEBUG && targetEnvironment(simulator)
/// Local examples for every home section, stored only in simulator-demo.store.
/// See docs/requirements.md §4.11. IDs are stable across launches and locales.
enum SimulatorDemoFixtures {
    struct Snapshot {
        let habits: [Habit]
        let habitRecords: [HabitRecord]
        let anniversaries: [Anniversary]
        let healthSummaries: [HealthSummary]
        let memo: MemoPad
        let letters: [Letter]
        let shoppingPlaces: [ShoppingPlace]
        let shoppingItems: [ShoppingItem]
    }

    static func snapshot(referenceDate: Date, calendar: Calendar = .current) -> Snapshot {
        let today = calendar.startOfDay(for: referenceDate)
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today)!
        }
        let habits = [
            Habit(id: identifier(namespace: "DE300000", index: 1), title: String(localized: "Meditation"),
                  iconName: "brain.head.profile", colorHex: "#F97316", schedule: .daily, createdAt: day(-30)),
            Habit(id: identifier(namespace: "DE300000", index: 2), title: String(localized: "Drink Water"),
                  iconName: "drop.fill", colorHex: "#0EA5E9", schedule: .custom(days: [.monday, .wednesday, .friday]),
                  createdAt: day(-30)),
            Habit(id: identifier(namespace: "DE300000", index: 3), title: String(localized: "Read 20 pages"),
                  iconName: "book.fill", colorHex: "#22C55E", schedule: .weekdays, createdAt: day(-30))
        ]
        var records: [HabitRecord] = []
        for offset in -6...0 {
            let date = day(offset)
            let dateIndex = calendar.ordinality(of: .day, in: .era, for: date)!
            for (index, habit) in habits.enumerated() where habit.schedule.isActive(on: date) {
                records.append(HabitRecord(
                    id: identifier(namespace: "DE310000", index: dateIndex * 10 + index),
                    habitID: habit.id, date: date, isCompleted: (abs(offset) + index) % 3 != 2
                ))
            }
        }
        let anniversaries = [
            Anniversary(id: identifier(namespace: "DE400000", index: 1), title: String(localized: "Next vacation"),
                        targetDate: day(45), type: .countdown, repeatsYearly: false),
            Anniversary(id: identifier(namespace: "DE400000", index: 2), title: String(localized: "Started Bullet Journal"),
                        targetDate: calendar.date(byAdding: .year, value: -2, to: today)!, type: .since,
                        repeatsYearly: true)
        ]
        let health = (-6...0).map { offset in
            let date = day(offset)
            var summary = HealthSummary(date: date)
            summary.id = identifier(namespace: "DE500000", index: calendar.ordinality(of: .day, in: .era, for: date)!)
            summary.steps = 6_800 + (offset + 6) * 450
            summary.sleepHours = 7.0 + Double((offset + 6) % 3) * 0.25
            summary.activeEnergy = 320 + Double((offset + 6) * 20)
            summary.moveMinutes = 45 + Double((offset + 6) * 5)
            summary.exerciseMinutes = 20 + Double((offset + 6) % 3 * 5)
            summary.standHours = 10
            summary.sleepEnd = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: date)
            summary.sleepStart = summary.sleepEnd?.addingTimeInterval(-(summary.sleepHours ?? 7) * 3_600)
            return summary
        }
        let place = ShoppingPlace(id: identifier(namespace: "DE700000", index: 1),
                                  name: String(localized: "simulator.demo.shopping.supermarket"))
        return Snapshot(
            habits: habits, habitRecords: records, anniversaries: anniversaries, healthSummaries: health,
            memo: MemoPad(text: String(localized: "simulator.demo.memo"), lastUpdatedAt: today),
            letters: [Letter(id: identifier(namespace: "DE600000", index: 1),
                             content: String(localized: "在宅で集中できた。コードレビューも褒められた。"),
                             createdAt: today, deliveryDate: day(30), status: .draft)],
            shoppingPlaces: [place],
            shoppingItems: [
                ShoppingItem(id: identifier(namespace: "DE710000", index: 1),
                             title: String(localized: "simulator.demo.shopping.milk"), placeID: place.id,
                             createdAt: today),
                ShoppingItem(id: identifier(namespace: "DE710000", index: 2),
                             title: String(localized: "simulator.demo.shopping.bread"), placeID: place.id,
                             createdAt: today.addingTimeInterval(1))
            ]
        )
    }

    private static func identifier(namespace: String, index: Int) -> UUID {
        UUID(uuidString: String(format: "\(namespace)-0000-4000-8000-%012d", index))!
    }
}
#endif
