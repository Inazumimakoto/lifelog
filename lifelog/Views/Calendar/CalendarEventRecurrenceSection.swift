import SwiftUI

/// Creation and editing share the same controls; scope is chosen when saving (§4.2).
struct CalendarEventRecurrenceSection: View {
    @ObservedObject var form: CalendarEventEditorFormState

    private var weekdays: [Int] {
        (0..<7).map { (CalendarWeekStart.current.rawValue - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        Section("繰り返し") {
            Picker("繰り返し", selection: Binding(
                get: { form.recurrenceFrequency },
                set: { form.selectRecurrenceFrequency($0) }
            )) {
                ForEach(CalendarEventEditorFormState.RecurrenceFrequency.allCases) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }

            if form.usesWeeklyRecurrence {
                VStack(alignment: .leading, spacing: 8) {
                    Text("曜日")
                    HStack(spacing: 4) {
                        ForEach(weekdays, id: \.self) { weekday in
                            weekdayButton(weekday)
                        }
                    }
                    if form.recurrenceWeekdays.isEmpty {
                        Text("曜日を1つ以上選んでください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            if form.isRepeating {
                Toggle("終了日を設定", isOn: $form.hasRecurrenceEnd)
                if form.hasRecurrenceEnd {
                    DatePicker("繰り返しの終了日", selection: $form.recurrenceEndDate,
                               in: form.recurrenceEndLowerBound...,
                               displayedComponents: .date)
                }
            }
            if form.isOccurrence {
                Text("保存時に変更する範囲を選べます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if form.originalEvent?.recurrenceRule != nil {
                Text("保存すると繰り返し予定全体に反映されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func weekdayButton(_ weekday: Int) -> some View {
        let selected = form.recurrenceWeekdays.contains(weekday)
        return Button {
            form.toggleRecurrenceWeekday(weekday)
        } label: {
            Text(form.calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                .font(.body.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(form.calendar.standaloneWeekdaySymbols[weekday - 1])
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
