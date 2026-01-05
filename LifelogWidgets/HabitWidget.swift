//
//  HabitWidget.swift
//  LifelogWidgets
//
//  Created for Widget Implementation
//

import WidgetKit
import SwiftUI
import SwiftData

struct HabitProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: Date(), habits: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> ()) {
        _Concurrency.Task { @MainActor in
            let entry = HabitEntry(date: Date(), habits: fetchHabits())
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> ()) {
        _Concurrency.Task { @MainActor in
            let entry = HabitEntry(date: Date(), habits: fetchHabits())
            
            // Refresh at end of day or often enough to catch app updates (e.g., 30 mins)
            let currentDate = Date()
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
            
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }

    @MainActor
    private func fetchHabits() -> [HabitWidgetModel] {
        do {
            let context = PersistenceController.shared.container.mainContext
            
            // 1. Fetch active habits
            var descriptor = FetchDescriptor<SDHabit>(
                predicate: #Predicate<SDHabit> { !$0.isArchived },
                sortBy: [SortDescriptor(\.orderIndex)]
            )
            let habits = try context.fetch(descriptor)
            
            // 2. Check completion for today
            let today = Calendar.current.startOfDay(for: Date())
            let activeHabits = habits.filter { $0.scheduleIsActive(on: today) }
            
            var results: [HabitWidgetModel] = []
            
            // Get records for this week (Sun-Sat)
            let calendar = Calendar.current
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
            
            for habit in activeHabits.prefix(3) {
                var completions: [Bool] = []
                for i in 0..<7 {
                    if let day = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                        let habitID = habit.id
                        // We can't easily access records relationship here because SDHabit definition didn't include explicit @Relationship(inverse:) in my snippet
                        // Wait, I didn't add @Relationship to SDHabit.
                        // I have to query SDHabitRecord directly.
                        
                        let recordsDesc = FetchDescriptor<SDHabitRecord>(
                            predicate: #Predicate { $0.habitID == habitID }
                        )
                        let records = (try? context.fetch(recordsDesc)) ?? []
                        let isCompleted = records.contains { calendar.isDate($0.date, inSameDayAs: day) }
                        completions.append(isCompleted)
                    } else {
                        completions.append(false)
                    }
                }
                
                results.append(HabitWidgetModel(
                    id: habit.id,
                    iconName: habit.iconName,
                    colorHex: habit.colorHex,
                    completions: completions
                ))
            }
            
            return results
        } catch {
            // Error during fetch - return empty
            return []
        }
    }
}

struct HabitWidgetModel: Identifiable {
    let id: UUID
    let iconName: String
    let colorHex: String
    let completions: [Bool] // 7 days (Mon-Sun or Sun-Sat)
}

struct HabitEntry: TimelineEntry {
    let date: Date
    let habits: [HabitWidgetModel]
}

struct HabitWidgetEntryView : View {
    var entry: HabitProvider.Entry

    var body: some View {
        VStack(spacing: 8) {
            // Header Days (M T W T F S S)
            HStack {
                Spacer().frame(width: 24) // Icon spacing
                ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.secondary)
                }
            }
            

            
            if entry.habits.isEmpty {
                Spacer()
                Text("習慣がありません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(entry.habits) { habit in
                    HStack {
                        // Icon
                        Image(systemName: habit.iconName)
                            .font(.caption)
                            .foregroundColor(Color(hex: habit.colorHex))
                            .frame(width: 24)
                        
                        // Dots
                        ForEach(0..<7) { index in
                            if index < habit.completions.count {
                                Circle()
                                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                                    .background(Circle().fill(habit.completions[index] ? Color(hex: habit.colorHex) : Color.clear))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 20)
                            } else {
                                Circle().frame(maxWidth: .infinity).hidden()
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// Color Hex Helper for Widget
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct HabitWidget: Widget {
    let kind: String = "HabitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitProvider()) { entry in
             if #available(iOS 17.0, *) {
                HabitWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                HabitWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("週間習慣トラッカー")
        .description("今週の習慣の達成状況を一目で確認できます。")
        .supportedFamilies([.systemMedium])
    }
}
