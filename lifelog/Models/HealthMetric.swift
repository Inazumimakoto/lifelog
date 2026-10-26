import Foundation

/// Destinations opened from the Health summary cards (§4.8).
enum HealthMetric: String, CaseIterable, Identifiable {
    case steps
    case sleep
    case fitness
    case wellness

    var id: Self { self }

    var title: String {
        switch self {
        case .steps: return String(localized: "歩数")
        case .sleep: return String(localized: "睡眠")
        case .fitness: return String(localized: "アクティビティ")
        case .wellness: return String(localized: "健康状態の推移")
        }
    }
}
