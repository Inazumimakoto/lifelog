import Foundation

extension Habit {
    /// Changing editor fields must retain the creation/archive metadata used by
    /// past-day eligibility and history.
    func applyingEditorValues(title: String, iconName: String, colorHex: String, schedule: HabitSchedule) -> Habit {
        var updated = self
        updated.title = title
        updated.iconName = iconName
        updated.colorHex = colorHex
        updated.schedule = schedule
        return updated
    }
}
