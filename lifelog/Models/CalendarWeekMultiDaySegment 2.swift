import SwiftUI

struct CalendarWeekMultiDaySegment: Identifiable {
    let id: String
    let eventID: UUID
    let title: String
    let categoryName: String
    let color: Color
    let lane: Int
    let startColumn: Int
    let endColumn: Int
    let continuesBeforeWeek: Bool
    let continuesAfterWeek: Bool
}
