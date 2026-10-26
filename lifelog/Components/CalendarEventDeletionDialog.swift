import SwiftUI

/// Uses the saved event's identity so an unsaved date or recurrence edit cannot
/// change which occurrence or series the deletion scope applies to (§4.2).
private struct CalendarEventDeletionDialog: ViewModifier {
    @Binding var isPresented: Bool
    let event: CalendarEvent?
    let onDelete: (() -> Void)?
    let onSkipWeek: (() -> Void)?
    let onEndSeries: (() -> Void)?
    let onDeleteSeries: (() -> Void)?
    let canDeleteWeek: () -> Bool
    @State private var presentation: Presentation?

    private struct Presentation {
        let event: CalendarEvent
        let canDeleteWeek: Bool
    }

    private var preparedIsPresented: Binding<Bool> {
        Binding(get: { isPresented && presentation != nil }, set: { isPresented = $0 })
    }

    private var title: LocalizedStringKey {
        let savedEvent = presentation?.event ?? event
        if savedEvent?.occurrenceReference != nil { return "予定の削除範囲を選択" }
        if savedEvent?.recurrenceRule != nil { return "繰り返し予定をすべて削除しますか？" }
        return "この予定を削除しますか？"
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: preparedIsPresented, titleVisibility: .visible, presenting: presentation) { selection in
            if selection.event.occurrenceReference != nil {
                if let onDelete {
                    Button("この回だけ削除", role: .destructive, action: onDelete)
                }
                if selection.canDeleteWeek, let onSkipWeek {
                    Button("この週の予定を削除", role: .destructive, action: onSkipWeek)
                }
                if let onEndSeries {
                    Button("これ以降の予定を削除", role: .destructive, action: onEndSeries)
                }
                if let onDeleteSeries {
                    Button("繰り返し予定をすべて削除", role: .destructive, action: onDeleteSeries)
                }
            } else if selection.event.recurrenceRule != nil {
                // The management list presents the series itself, without a selected occurrence.
                if let deleteSeries = onDeleteSeries ?? onDelete {
                    Button("繰り返し予定をすべて削除", role: .destructive, action: deleteSeries)
                }
            } else if let onDelete {
                Button("削除", role: .destructive, action: onDelete)
            }
            Button("キャンセル", role: .cancel) { }
        } message: { selection in
            if selection.event.occurrenceReference != nil, onDeleteSeries != nil {
                Text("「繰り返し予定をすべて削除」を選ぶと、過去の予定と休み・変更の設定も削除されます。")
            } else if selection.event.recurrenceRule != nil && selection.event.occurrenceReference == nil {
                Text("過去の予定と休み・変更の設定も削除されます。")
            }
        }
        .onChange(of: isPresented, initial: true) { _, isRequested in
            guard isRequested else {
                if presentation != nil { presentation = nil }
                return
            }
            guard presentation == nil else { return }
            guard let event else {
                isPresented = false
                return
            }
            // The store query can expand a week of recurring events. Run it
            // once per requested presentation, never while editing or scrolling.
            let includesWeek = event.occurrenceReference != nil && onSkipWeek != nil && canDeleteWeek()
            presentation = Presentation(event: event, canDeleteWeek: includesWeek)
        }
    }
}

extension View {
    func calendarEventDeletionDialog(
        isPresented: Binding<Bool>,
        event: CalendarEvent?,
        onDelete: (() -> Void)?,
        onSkipWeek: (() -> Void)?,
        onEndSeries: (() -> Void)?,
        onDeleteSeries: (() -> Void)?,
        canDeleteWeek: @escaping () -> Bool = { false }
    ) -> some View {
        modifier(CalendarEventDeletionDialog(isPresented: isPresented,
                                             event: event,
                                             onDelete: onDelete,
                                             onSkipWeek: onSkipWeek,
                                             onEndSeries: onEndSeries,
                                             onDeleteSeries: onDeleteSeries,
                                             canDeleteWeek: canDeleteWeek))
    }
}
