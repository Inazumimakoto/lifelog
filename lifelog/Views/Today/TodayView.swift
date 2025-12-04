//
//  TodayView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI
import PhotosUI

struct TodayView: View {
    @StateObject private var viewModel: TodayViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showTaskManager = false
    @State private var showTaskEditor = false
    @State private var showDiaryEditor = false
    @State private var showEventEditor = false
    @State private var showMemoEditor = false
    @State private var showAnalysisExport = false
    @State private var editingEvent: CalendarEvent?
    @State private var editingTask: Task?
    @State private var eventToDelete: CalendarEvent?
    @State private var taskToDelete: Task?
    @State private var showEventDeleteConfirmation = false
    @State private var showTaskDeleteConfirmation = false
    private let memoPlaceholder = "買い物リストや気づいたことを書いておけます"
    private let store: AppDataStore
    @State private var didAppear = false
    @State private var calendarSyncTrigger = 0

    init(store: AppDataStore) {
        self.store = store
        _viewModel = StateObject(wrappedValue: TodayViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                eventsSection
//                todayTimelineSection
                tasksSection
                memoSection
                habitsSection
                healthSection
                diarySection
            }
            .padding()
        }
        .task(id: calendarSyncTrigger) {
            await syncCalendarsIfNeeded()
        }
        .onChange(of: scenePhase, initial: false) { oldPhase, newPhase in
            if oldPhase != .active && newPhase == .active {
                calendarSyncTrigger += 1
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showMemoEditor = true
                } label: {
                    Image(systemName: "note.text")
                }
                Button {
                    showTaskManager = true
                } label: {
                    Image(systemName: "checklist")
                }
                Menu {
                    Button("予定を追加") {
                        showEventEditor = true
                    }
                    Button("タスクを追加") {
                        showTaskEditor = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fullScreenCover(isPresented: $showMemoEditor) {
            NavigationStack {
                MemoEditorView(store: store)
            }
        }
        .sheet(isPresented: $showTaskManager) {
            NavigationStack {
                TasksView(store: store)
            }
        }
        .sheet(isPresented: $showTaskEditor) {
            NavigationStack {
                TaskEditorView(defaultDate: viewModel.date) { task in
                    store.addTask(task)
                }
            }
        }
        .sheet(isPresented: $showDiaryEditor) {
            NavigationStack {
                DiaryEditorView(store: store, date: viewModel.date)
            }
        }
        .sheet(isPresented: $showAnalysisExport) {
            AnalysisExportView(store: store)
        }
        .sheet(isPresented: $showEventEditor) {
            NavigationStack {
                CalendarEventEditorView(defaultDate: viewModel.date) { event in
                    store.addCalendarEvent(event)
                }
            }
        }
        .sheet(item: $editingEvent) { event in
            NavigationStack {
                CalendarEventEditorView(event: event) { updated in
                    store.updateCalendarEvent(updated)
                }
            }
        }
        .sheet(item: $editingTask) { task in
            NavigationStack {
                TaskEditorView(task: task,
                               defaultDate: task.startDate ?? task.endDate ?? viewModel.date) { updated in
                    store.updateTask(updated)
                }
            }
        }
        .confirmationDialog("予定を削除", isPresented: $showEventDeleteConfirmation) {
            Button("削除", role: .destructive) {
                if let event = eventToDelete {
                    viewModel.deleteEvent(event)
                }
                eventToDelete = nil
            }
            Button("キャンセル", role: .cancel) {
                eventToDelete = nil
            }
        } message: {
            if let event = eventToDelete {
                Text("\"\(event.title)\" を削除しますか？")
            }
        }
        .confirmationDialog("タスクを削除", isPresented: $showTaskDeleteConfirmation) {
            Button("削除", role: .destructive) {
                if let task = taskToDelete {
                    viewModel.deleteTask(task)
                }
                taskToDelete = nil
            }
            Button("キャンセル", role: .cancel) {
                taskToDelete = nil
            }
        } message: {
            if let task = taskToDelete {
                Text("\"\(task.title)\" を削除しますか？")
            }
        }
    }

    private func syncCalendarsIfNeeded() async {
        guard didAppear == false else {
            await viewModel.syncExternalCalendarsIfNeeded()
            return
        }
        didAppear = true
        await viewModel.syncExternalCalendarsIfNeeded()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                Text(viewModel.date.jaYearMonthDayString)
                    .font(.largeTitle.bold())
                Text(viewModel.date.jaWeekdayWideString)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text("今日の予定・タスク・記録をここでまとめて確認できます。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventsSection: some View {
        SectionCard(title: "カレンダー",
                    actionTitle: "予定を追加",
                    action: { showEventEditor = true }) {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.events.isEmpty {
                    Text("本日の予定はありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.events) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(color(for: event.calendarName))
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.body.weight(.semibold))
                            Label(eventTimeLabel(event), systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if event.calendarName.isEmpty == false {
                                Text(event.calendarName)
                                    .font(.caption2)
                                    .foregroundStyle(color(for: event.calendarName))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(color(for: event.calendarName).opacity(0.15), in: Capsule())
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Button {
                            editingEvent = event
                                } label: {
                                    Label("編集", systemImage: "square.and.pencil")
                                }
                                Button(role: .destructive) {
                                    eventToDelete = event
                                    showEventDeleteConfirmation = true
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        if event.id != viewModel.events.last?.id {
                            Divider()
                        }
                    }
                }
                Text("予定を追加するとカレンダーとホームで共有されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.calendarAccessDenied {
                    Text("設定 > プライバシーとセキュリティ > カレンダーでlifelogへのアクセスを許可すると、外部カレンダーの予定が表示されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var tasksSection: some View {
        SectionCard(title: "今日のタスク",
                    actionTitle: "タスクを追加",
                    action: { showTaskEditor = true }) {
            VStack(spacing: 12) {
                if viewModel.tasksDueToday.isEmpty {
                    Text("今日のタスクはありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.tasksDueToday) { task in
                        VStack(alignment: .leading, spacing: 8) {
                            TaskRowView(task: task, onToggle: {
                                viewModel.toggleTask(task)
                            })
                            HStack(spacing: 12) {
                                Button {
                                    editingTask = task
                                } label: {
                                    Label("編集", systemImage: "square.and.pencil")
                                }
                                Button(role: .destructive) {
                                    taskToDelete = task
                                    showTaskDeleteConfirmation = true
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        if task.id != viewModel.tasksDueToday.last?.id {
                            Divider()
                        }
                    }
                }
                if viewModel.completedTasksToday.isEmpty == false {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("完了済み")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(viewModel.completedTasksToday) { task in
                            VStack(alignment: .leading, spacing: 8) {
                                TaskRowView(task: task, onToggle: {
                                    viewModel.toggleTask(task)
                                })
                                HStack(spacing: 12) {
                                    Button {
                                        editingTask = task
                                    } label: {
                                        Label("編集", systemImage: "square.and.pencil")
                                    }
                                    Button(role: .destructive) {
                                        taskToDelete = task
                                        showTaskDeleteConfirmation = true
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            if task.id != viewModel.completedTasksToday.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("別日のタスクや詳細な整理はタスクリストで管理してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        showTaskManager = true
                    } label: {
                        Label("タスクリストを開く", systemImage: "calendar.badge.plus")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private var memoSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("メモ")
                        .font(.headline)
                    Spacer()
                    Button {
                        showMemoEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                }

                let trimmed = viewModel.memoPad.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    Text(memoPlaceholder)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(trimmed)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let lastUpdated = viewModel.memoPad.lastUpdatedAt {
                    Text("最終更新: \(lastUpdated.memoPadDisplayString())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showMemoEditor = true
        }
    }

    private var habitsSection: some View {
        SectionCard(title: "習慣チェック") {
            if viewModel.habitStatuses.isEmpty {
                Text("本日分の習慣は登録されていません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.habitStatuses) { status in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.toggleHabit(status.habit)
                            }
                        } label: {
                            HStack {
                                Label(status.habit.title, systemImage: status.habit.iconName)
                                    .foregroundStyle(Color(hex: status.habit.colorHex) ?? .accentColor)
                                Spacer()
                                Image(systemName: status.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(status.isCompleted ? Color.accentColor : .secondary)
                                    .scaleEffect(status.isCompleted ? 1.05 : 0.95)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: status.isCompleted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var healthSection: some View {
        SectionCard(title: "ヘルスサマリー") {
            HStack(spacing: 16) {
                StatTile(title: "歩数", value: "\(viewModel.healthSummary?.steps ?? 0)")
                StatTile(title: "睡眠", value: String(format: "%.1f h", viewModel.healthSummary?.sleepHours ?? 0))
                StatTile(title: "エネルギー", value: String(format: "%.0f kcal", viewModel.healthSummary?.activeEnergy ?? 0))
            }
        }
    }

    private var diarySection: some View {
        SectionCard(title: "日記") {
            VStack(alignment: .leading, spacing: 8) {
                if let entry = viewModel.diaryEntry, entry.text.isEmpty == false {
                    Text(entry.text)
                        .font(.body)
                        .lineLimit(3)
                } else {
                    Text("まだ記録がありません。今日感じたことを書き残しましょう。")
                        .foregroundStyle(.secondary)
                }
                Button {
                    showDiaryEditor = true
                } label: {
                    Text("日記を開く")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    showAnalysisExport = true
                } label: {
                    Label("AI用にデータを書き出す", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func eventTimeLabel(_ event: CalendarEvent) -> String {
        if event.isAllDay {
            return "終日"
        }
        return "\(event.startDate.formattedTime()) - \(event.endDate.formattedTime())"
    }

    private func color(for category: String) -> Color {
        CategoryPalette.color(for: category)
    }

    // タイムライン仕様: docs/requirements.md 4.1 + docs/ui-guidelines.md (Today)
    private var todayTimelineSection: some View {
        TodayTimelineView(items: viewModel.timelineItems, anchorDate: viewModel.date)
    }
}
