import Foundation

/// Rolling history windows ending on the selected calendar day (§4.8).
enum HealthHistoryPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case halfYear
    case year

    var id: Self { self }

    var title: String {
        switch self {
        case .week: return String(localized: "週")
        case .month: return String(localized: "1か月")
        case .halfYear: return String(localized: "6か月")
        case .year: return String(localized: "1年")
        }
    }

    func dateRange(endingOn date: Date, calendar: Calendar = .current) -> Range<Date> {
        let day = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let start = calendar.date(byAdding: component, value: -componentCount, to: end) ?? day
        return start..<end
    }

    /// Moves one complete window without assuming that every day is 24 hours.
    func shiftedEndDate(from date: Date, by direction: Int, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: component, value: componentCount * direction, to: day) ?? day
    }

    private var component: Calendar.Component {
        switch self {
        case .week: return .day
        case .month, .halfYear: return .month
        case .year: return .year
        }
    }

    private var componentCount: Int {
        switch self {
        case .week: return 7
        case .month: return 1
        case .halfYear: return 6
        case .year: return 1
        }
    }
}
