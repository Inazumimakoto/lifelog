import SwiftUI

/// docs/ui-guidelines.md §Today: keep the name and checkbox anchored on one line.
struct TodayHabitRow: View {
    let status: TodayViewModel.DailyHabitStatus

    private var habitColor: Color {
        Color(hex: status.habit.colorHex) ?? .accentColor
    }

    private var accessibilityValue: String {
        let completion = status.isCompleted ? String(localized: "完了") : String(localized: "未完了")
        guard status.currentStreak > 0 else { return completion }
        return completion + ", " + String(localized: "\(status.currentStreak)日連続")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.habit.iconName)
                .font(.system(size: 17))
                .foregroundStyle(habitColor)
                .frame(width: 24, height: 26)
                .accessibilityHidden(true)

            Text(status.habit.title)
                .foregroundStyle(habitColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if status.currentStreak > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                    Text("\(status.currentStreak)日")
                        .monospacedDigit()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.orange.opacity(0.12), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }

            AnimatedCheckmark(isCompleted: status.isCompleted, color: habitColor, size: 26)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 26)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: status.habit.title))
        .accessibilityValue(accessibilityValue)
    }
}

#Preview("Home habit streaks") {
    VStack(spacing: 12) {
        ForEach([0, 1, 14, 100], id: \.self) { streak in
            TodayHabitRow(status: .init(
                habit: Habit(title: String(localized: "読書"), iconName: "book", colorHex: "#3478F6", schedule: .daily),
                record: nil,
                currentStreak: streak
            ))
        }
    }
    .padding()
}
