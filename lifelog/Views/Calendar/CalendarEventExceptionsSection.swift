import SwiftUI

struct CalendarEventExceptionsSection: View {
    let exceptions: [CalendarEventException]
    let onRestore: (CalendarEventException) -> Void
    @State private var restoredIDs: Set<UUID> = []

    private var visibleExceptions: [CalendarEventException] {
        exceptions.filter { !restoredIDs.contains($0.id) }
            .sorted { $0.originalStartDate < $1.originalStartDate }
    }

    var body: some View {
        if !visibleExceptions.isEmpty {
            Section("休み・変更した日") {
                ForEach(visibleExceptions) { exception in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exception.originalStartDate, format: .dateTime.year().month().day().weekday())
                            Text(exception.replacement == nil ? LocalizedStringKey("お休み") : LocalizedStringKey("変更あり"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("元に戻す") {
                            onRestore(exception)
                            restoredIDs.insert(exception.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}
