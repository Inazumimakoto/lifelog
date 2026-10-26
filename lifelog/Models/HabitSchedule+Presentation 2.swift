import Foundation

extension HabitSchedule {
    var displayDescription: String {
        switch self {
        case .daily:
            return String(localized: "毎日")
        case .weekdays:
            return String(localized: "平日")
        case .custom(let days):
            return days.sorted { $0.rawValue < $1.rawValue }.map(\.shortLabel).joined(separator: " ")
        }
    }
}
