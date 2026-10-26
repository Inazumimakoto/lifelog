//
//  CalendarEventEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct CalendarEventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var formState: CalendarEventEditorFormState
    @StateObject private var detailDraft: LongFormTextDraft
    @ObservedObject private var categoryPalette = CategoryPaletteObserver.shared
    @State private var isShowingCategorySelection = false
    @State private var showDeletionDialog = false
    @State private var didFinishEditing = false
    @State private var saveFlow: SaveFlowRequest?
    @State private var didSaveInFlow = false
    @State private var saveError: String?

    var onSave: (CalendarEvent) -> Void
    var onDelete: (() -> Void)?
    var onSkipWeek: (() -> Void)?
    var onEndSeries: (() -> Void)?
    var exceptions: [CalendarEventException]
    var onRestoreException: ((CalendarEventException) -> Void)?
    var onDeleteSeries: (() -> Void)?
    var canDeleteWeek: () -> Bool

    private let originalEvent: CalendarEvent?
    private let defaultDate: Date
    private let editStore: AppDataStore?
    private var isReadOnly: Bool { originalEvent?.sourceCalendarIdentifier != nil }
    private var isOccurrence: Bool { originalEvent?.occurrenceReference != nil }

    private struct SaveFlowRequest: Identifiable {
        let id = UUID()
        let store: AppDataStore
        let original: CalendarEvent
        let edited: CalendarEvent
        let allowsOccurrence: Bool
        let initialPlan: CalendarEventEditPlan?
    }

    init(defaultDate: Date = Date(),
         event: CalendarEvent? = nil,
         onSave: @escaping (CalendarEvent) -> Void,
         onDelete: (() -> Void)? = nil,
         onSkipWeek: (() -> Void)? = nil,
         onEndSeries: (() -> Void)? = nil,
         exceptions: [CalendarEventException] = [],
         onRestoreException: ((CalendarEventException) -> Void)? = nil,
         onDeleteSeries: (() -> Void)? = nil,
         canDeleteWeek: @escaping () -> Bool = { false },
         editStore: AppDataStore? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.onSkipWeek = onSkipWeek
        self.onEndSeries = onEndSeries
        let seriesID = event?.occurrenceReference?.seriesID ?? event?.id
        self.exceptions = exceptions.filter { $0.seriesID == seriesID }
        self.onRestoreException = onRestoreException
        self.onDeleteSeries = onDeleteSeries
        self.canDeleteWeek = canDeleteWeek
        self.editStore = editStore
        self.originalEvent = event
        self.defaultDate = defaultDate
        let formState = CalendarEventEditorFormState(event: event, defaultDate: defaultDate)
        _formState = StateObject(wrappedValue: formState)
        _detailDraft = StateObject(wrappedValue: LongFormTextDraft(text: formState.detail))
    }

    var body: some View {
        Form {
            Section("予定") {
                TextField("タイトル", text: $formState.title)
                DetailMemoEditor(draft: detailDraft) { newValue in
                    formState.cacheDraft(detailOverride: newValue)
                }
                Button(action: { isShowingCategorySelection = true }) {
                    HStack {
                        Text("カテゴリ")
                        Spacer()
                        Circle()
                            .fill(CategoryPalette.color(for: formState.category))
                            .frame(width: 10, height: 10)
                        Text(CategoryPalette.displayName(for: formState.category))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }
            .disabled(isReadOnly)

            Section("URL") {
                ScheduleLinkEditor(urlString: $formState.urlString, isReadOnly: isReadOnly)
            }

            Section("時間") {
                Toggle("終日", isOn: $formState.isAllDay)
                DatePicker("開始", selection: $formState.startDate, displayedComponents: formState.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .onChange(of: formState.startDate) { _, newValue in
                        if formState.endDate < newValue {
                            formState.endDate = newValue
                        }
                        if formState.isAllDay {
                            formState.startDate = formState.calendar.startOfDay(for: newValue)
                        }
                        formState.recurrenceEndDate = max(formState.recurrenceEndDate, formState.recurrenceEndLowerBound)
                        // 開始前モードの場合のみ、reminderDateを連動更新
                        if formState.useRelativeReminder {
                            formState.reminderDate = newValue.addingTimeInterval(-Double(formState.reminderMinutes * 60))
                        }
                    }
                DatePicker("終了", selection: $formState.endDate, in: formState.startDate..., displayedComponents: formState.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .onChange(of: formState.endDate) { _, newValue in
                        formState.endDate = max(newValue, formState.startDate)
                        if formState.isAllDay {
                            formState.endDate = formState.calendar.startOfDay(for: formState.endDate)
                        }
                    }
            }
            .disabled(isReadOnly)
            
            CalendarEventRecurrenceSection(form: formState)
                .disabled(isReadOnly)

            Section("通知") {
                Toggle("リマインダー", isOn: $formState.hasReminder)
                if formState.hasReminder {
                    if !formState.isRepeating || isOccurrence {
                        Picker("通知方法", selection: $formState.useRelativeReminder) {
                            Text("開始前").tag(true)
                            Text("日時指定").tag(false)
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Text("繰り返し予定は、各回の開始前に通知します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    
                    if formState.useRelativeReminder {
                        EventReminderTimingPicker(title: "タイミング", minutesBefore: $formState.reminderMinutes)
                        .onChange(of: formState.reminderMinutes) { _, newValue in
                            formState.reminderDate = formState.startDate.addingTimeInterval(-Double(newValue * 60))
                        }
                    } else {
                        DatePicker("通知日時", selection: $formState.reminderDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .disabled(isReadOnly)
            
            if !isReadOnly, let onRestoreException {
                CalendarEventExceptionsSection(exceptions: exceptions, onRestore: onRestoreException)
            }

            if originalEvent != nil && (onDelete != nil || onDeleteSeries != nil) && !isReadOnly {
                Section {
                    Button("予定を削除", role: .destructive) {
                        showDeletionDialog = true
                    }
                }
            }
        }
        .environment(\.calendar, formState.calendar)
        .environment(\.timeZone, formState.calendar.timeZone)
        .navigationTitle(originalEvent == nil ? "予定を追加" : "予定を編集")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
                .disabled(isReadOnly || !formState.canSave)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) {
                    didFinishEditing = true
                    formState.clearCachedDraft()
                    dismiss()
                }
            }
        }
        .onChange(of: formState.draft) { _, _ in
            formState.cacheDraft(detailOverride: detailDraft.text)
        }
        .onChange(of: formState.isAllDay) { _, newValue in
            if newValue {
                let calendar = formState.calendar
                formState.startDate = calendar.startOfDay(for: formState.startDate)
                formState.endDate = calendar.startOfDay(for: max(formState.endDate, formState.startDate))
            }
        }
        .sheet(isPresented: $isShowingCategorySelection) {
            CategorySelectionView(selectedCategory: Binding(
                get: { formState.category },
                set: { formState.selectCategory($0) }
            ))
        }
        .sheet(item: $saveFlow, onDismiss: {
            if didSaveInFlow { finishEditing() }
        }) { request in
            CalendarEventSaveFlowView(store: request.store,
                                      original: request.original,
                                      edited: request.edited,
                                      allowsOccurrence: request.allowsOccurrence,
                                      initialPlan: request.initialPlan) {
                didSaveInFlow = true
            }
            .environment(\.calendar, formState.calendar)
            .environment(\.timeZone, formState.calendar.timeZone)
        }
        .alert("予定を保存できませんでした", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .calendarEventDeletionDialog(isPresented: $showDeletionDialog,
                                     event: originalEvent,
                                     onDelete: finishingAfterDeletion(onDelete),
                                     onSkipWeek: finishingAfterDeletion(onSkipWeek),
                                     onEndSeries: finishingAfterDeletion(onEndSeries),
                                     onDeleteSeries: finishingAfterDeletion(onDeleteSeries),
                                     canDeleteWeek: canDeleteWeek)
        .onDisappear {
            if !didFinishEditing && !isReadOnly {
                formState.cacheDraft(detailOverride: detailDraft.text)
            }
        }
    }

    private func save() {
        let edited = formState.makeEvent(detailOverride: detailDraft.text)
        // Cached drafts retain their original baseline for safe changed-field
        // comparison. Never mix that draft with the outer view's newer snapshot.
        guard let original = formState.originalEvent,
              original.recurrenceRule != nil || original.occurrenceReference != nil else {
            onSave(edited)
            finishEditing()
            return
        }
        guard let editStore else {
            saveError = String(localized: "画面を開き直して、もう一度お試しください。")
            return
        }

        didSaveInFlow = false
        if original.occurrenceReference != nil {
            saveFlow = SaveFlowRequest(store: editStore, original: original, edited: edited,
                                       allowsOccurrence: !formState.hasRecurrenceRuleChanges, initialPlan: nil)
            return
        }
        do {
            let plan = try editStore.prepareCalendarEventEdit(original: original, edited: edited, scope: .series)
            // Turning a whole series into one event needs explicit review even
            // when no exceptions are affected.
            if !plan.unmatchedExceptions.isEmpty || edited.recurrenceRule == nil {
                saveFlow = SaveFlowRequest(store: editStore, original: original, edited: edited,
                                           allowsOccurrence: false, initialPlan: plan)
            } else {
                try editStore.applyCalendarEventEdit(plan)
                finishEditing()
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func finishEditing() {
        didFinishEditing = true
        formState.clearCachedDraft()
        dismiss()
    }

    private func finishingAfterDeletion(_ action: (() -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        return {
            action()
            finishEditing()
        }
    }
}
