import Foundation

/// Read task presentation fields without copying persisted widget rows into domain models.
protocol TaskPresentationSource {
    var title: String { get }
    var priority: TaskPriority { get }
    var startDate: Date? { get }
    var endDate: Date? { get }
    var dateOnlyTimeZoneIdentifier: String? { get }
}

extension TaskPresentationSource {
    var dateOnlyTimeZoneIdentifier: String? { nil }
}

extension Task: TaskPresentationSource {}
extension SDTask: TaskPresentationSource {}
