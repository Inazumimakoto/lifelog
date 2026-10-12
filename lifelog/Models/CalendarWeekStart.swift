import Foundation

/// One display preference shared by the calendar, schedule widget and wallpaper (§4.2).
nonisolated enum CalendarWeekStart: Int, CaseIterable, Identifiable, Sendable {
    case sunday = 1
    case monday = 2

    static let storageKey = "Calendar_WeekStart_V1"

    @MainActor static var defaults: UserDefaults {
        UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? .standard
    }

    @MainActor static var current: CalendarWeekStart {
        load(from: defaults)
    }

    static func load(from defaults: UserDefaults) -> CalendarWeekStart {
        CalendarWeekStart(rawValue: defaults.integer(forKey: storageKey)) ?? .sunday
    }

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sunday: return String(localized: "calendar.weekStart.sunday")
        case .monday: return String(localized: "calendar.weekStart.monday")
        }
    }

    var calendar: Calendar {
        applying(to: .autoupdatingCurrent)
    }

    func applying(to calendar: Calendar) -> Calendar {
        var calendar = calendar
        calendar.firstWeekday = rawValue
        return calendar
    }

    func weekdaySymbols(in calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(rawValue - 1 + $0) % 7] }
    }
}
