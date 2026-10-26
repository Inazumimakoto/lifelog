import SwiftUI

/// Shared reminder choices for category defaults and individual events.
/// docs/requirements.md §4.9: support short notice without crowding a segmented control.
struct EventReminderTimingPicker: View {
    let title: LocalizedStringKey
    @Binding var minutesBefore: Int

    var body: some View {
        Picker(title, selection: $minutesBefore) {
            Text("1分前").tag(1)
            Text("2分前").tag(2)
            Text("3分前").tag(3)
            Text("5分前").tag(5)
            Text("10分前").tag(10)
            Text("15分前").tag(15)
            Text("30分前").tag(30)
            Text("1時間前").tag(60)
            Text("1日前").tag(1440)
        }
        .pickerStyle(.menu)
    }
}
