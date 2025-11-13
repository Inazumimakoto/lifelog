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
    @State private var showTaskManager = false
    @State private var showDiaryEditor = false
    @State private var showEventEditor = false
    @State private var editingEvent: CalendarEvent?
    private let store: AppDataStore

    init(store: AppDataStore) {
        self.store = store
        _viewModel = StateObject(wrappedValue: TodayViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                eventsSection
                todayTimelineSection
                tasksSection
                habitsSection
                healthSection
                diarySection
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTaskManager = true
                } label: {
                    Image(systemName: "checklist")
                }
            }
        }
        .sheet(isPresented: $showTaskManager) {
            NavigationStack {
                TasksView(store: store)
            }
        }
        .sheet(isPresented: $showDiaryEditor) {
            NavigationStack {
                DiaryEditorView(store: store, date: viewModel.date)
            }
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.date, style: .date)
                .font(.largeTitle.bold())
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
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(color(for: event.calendarName))
                                .frame(width: 10, height: 10)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.body.weight(.semibold))
                                Label("\(event.startDate.formattedTime()) - \(event.endDate.formattedTime())", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(event.calendarName)
                                    .font(.caption2)
                                    .foregroundStyle(color(for: event.calendarName))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(color(for: event.calendarName).opacity(0.15), in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingEvent = event
                        }
                        if event.id != viewModel.events.last?.id {
                            Divider()
                        }
                    }
                }
                Text("予定を追加するとジャーナルとTodayで共有されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tasksSection: some View {
        SectionCard(title: "今日のタスク",
                    actionTitle: "追加",
                    action: { showTaskManager = true }) {
            VStack(spacing: 12) {
                if viewModel.tasksDueToday.isEmpty {
                    Text("今日が期限のタスクはありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.tasksDueToday) { task in
                        TaskRowView(task: task) {
                            viewModel.toggleTask(task)
                        }
                        if task.id != viewModel.tasksDueToday.last?.id {
                            Divider()
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("別日のタスクを追加したい場合はフルタスクリストで期限を設定してください。")
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
                            viewModel.toggleHabit(status.habit)
                        } label: {
                            HStack {
                                Label(status.habit.title, systemImage: status.habit.iconName)
                                    .foregroundStyle(Color(hex: status.habit.colorHex) ?? .accentColor)
                                Spacer()
                                Image(systemName: status.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(status.isCompleted ? Color.accentColor : .secondary)
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
            }
        }
    }

    private func color(for category: String) -> Color {
        switch category.lowercased() {
        case let name where name.contains("work"):
            return .orange
        case let name where name.contains("personal"):
            return .blue
        case let name where name.contains("wellness"):
            return .green
        default:
            return .accentColor
        }
    }

    // タイムライン仕様: docs/requirements.md 4.1 + docs/ui-guidelines.md (Today)
    private var todayTimelineSection: some View {
        let items = viewModel.timelineItems
        return SectionCard(title: "今日のタイムライン") {
            if items.isEmpty {
                Text("今日の予定・タスクはありません")
                    .foregroundStyle(.secondary)
            } else {
                TodayTimelineView(items: items)
                    .frame(height: 200)
                Text("※時間軸は 6:00〜24:00。予定やタスクはタップで詳細を確認できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
