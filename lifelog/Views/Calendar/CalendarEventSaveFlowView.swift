import SwiftUI

/// One sheet owns scope selection and impact review, avoiding presentation races.
struct CalendarEventSaveFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    let store: AppDataStore
    let original: CalendarEvent
    let edited: CalendarEvent
    let allowsOccurrence: Bool
    let onSaved: () -> Void
    @State private var reviewPlan: CalendarEventEditPlan?
    @State private var preservingUnmatchedChanges = true
    @State private var saveError: String?

    init(store: AppDataStore, original: CalendarEvent, edited: CalendarEvent,
         allowsOccurrence: Bool, initialPlan: CalendarEventEditPlan? = nil,
         onSaved: @escaping () -> Void) {
        self.store = store
        self.original = original
        self.edited = edited
        self.allowsOccurrence = allowsOccurrence
        self.onSaved = onSaved
        _reviewPlan = State(initialValue: initialPlan)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let plan = reviewPlan {
                    impactReview(plan)
                } else {
                    scopeSelection
                }
            }
            .navigationTitle(reviewPlan == nil ? LocalizedStringKey("変更する予定を選択") : LocalizedStringKey("変更内容を確認"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", role: .cancel) { dismiss() }
                }
                if let plan = reviewPlan {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("変更を保存") { apply(plan) }
                    }
                }
            }
            .alert("予定を保存できませんでした", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone).weekday()
    }

    private var dateTimeFormat: Date.FormatStyle {
        Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
    }

    @ViewBuilder
    private var scopeSelection: some View {
        Section {
            if allowsOccurrence {
                Button("この回だけ変更") { prepare(.occurrence) }
            }
            Button("これ以降の予定を変更") { prepare(.future) }
            Button("繰り返し予定をすべて変更") { prepare(.series) }
        }

        Section {
            if let reference = original.occurrenceReference {
                Text(reference.originalStartDate, format: dateFormat)
                Text("変更範囲は、振替前の開催日を基準にします。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if edited.recurrenceRule == nil {
                Text("「これ以降」は過去の予定と選んだ回を残し、それ以降の繰り返しを終了します。「すべて」は繰り返し全体を1件の予定に置き換えます。")
            } else if !allowsOccurrence {
                Text("繰り返しの設定は、この回以降または予定全体に適用します。")
            }
        }
    }

    @ViewBuilder
    private func impactReview(_ plan: CalendarEventEditPlan) -> some View {
        Section {
            Text(scopeLabel(plan.scope))
                .font(.headline)
            if edited.recurrenceRule == nil && plan.scope == .series {
                Text("繰り返し予定全体を、この1件の予定に置き換えます。")
            }
        }

        if !plan.unmatchedExceptions.isEmpty {
            Section {
                Text("繰り返しの変更により、次の休み・変更は新しい予定に引き継げません。")
            }
            Section("影響を受ける休み・変更") {
                ForEach(plan.unmatchedExceptions.sorted { $0.originalStartDate < $1.originalStartDate }) { exception in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exception.originalStartDate, format: dateFormat)
                        Text(exception.replacement == nil ? LocalizedStringKey("お休み") : LocalizedStringKey("変更あり"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let replacement = exception.replacement {
                            Text(replacement.title)
                                .font(.subheadline)
                            Text(replacement.startDate, format: dateTimeFormat)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                if plan.unmatchedExceptions.contains(where: { $0.replacement != nil }) {
                    Toggle("変更した予定を単発の予定として残す", isOn: $preservingUnmatchedChanges)
                    Text("休みの設定は削除されます。残す設定をオフにすると、変更した予定も削除されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("これらの休みの設定は削除されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scopeLabel(_ scope: CalendarEventEditScope) -> LocalizedStringKey {
        switch scope {
        case .occurrence: return "この回だけ変更"
        case .future: return "これ以降の予定を変更"
        case .series: return "繰り返し予定をすべて変更"
        }
    }

    private func prepare(_ scope: CalendarEventEditScope) {
        do {
            let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: scope)
            if plan.unmatchedExceptions.isEmpty {
                apply(plan)
            } else {
                preservingUnmatchedChanges = true
                reviewPlan = plan
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func apply(_ plan: CalendarEventEditPlan) {
        do {
            try store.applyCalendarEventEdit(plan, preservingUnmatchedChanges: preservingUnmatchedChanges)
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
