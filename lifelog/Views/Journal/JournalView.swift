//
//  JournalView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct JournalView: View {
    private let store: AppDataStore
    @StateObject private var viewModel: JournalViewModel
    @State private var showTaskEditor = false
    @State private var showEventEditor = false
    @State private var editingEvent: CalendarEvent?
    @State private var editingTask: Task?
    @State private var showAddMenu = false
    @State private var pendingAddDate: Date?
    @State private var newItemDate: Date?

    init(store: AppDataStore) {
        self.store = store
        _viewModel = StateObject(wrappedValue: JournalViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                modePicker
                calendarSwitcher
                Text("※日付をダブルタップすると予定やタスクを追加できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                contentArea
            }
            .padding()
        }
        .navigationTitle("カレンダー")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("タスクを追加") {
                        newItemDate = viewModel.selectedDate
                        showTaskEditor = true
                    }
                    Button("予定を追加") {
                        newItemDate = viewModel.selectedDate
                        showEventEditor = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showTaskEditor) {
            NavigationStack {
                TaskEditorView(defaultDate: newItemDate ?? viewModel.selectedDate) { task in
                    store.addTask(task)
                }
            }
        }
        .sheet(isPresented: $showEventEditor) {
            NavigationStack {
                CalendarEventEditorView(defaultDate: newItemDate ?? viewModel.selectedDate) { event in
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
                               defaultDate: task.startDate ?? task.endDate ?? viewModel.selectedDate) { updated in
                    store.updateTask(updated)
                }
            }
        }
        .onChange(of: viewModel.displayMode) { newMode in
            viewModel.alignAnchorIfNeeded(for: newMode)
        }
        .confirmationDialog("この日に何を追加しますか？", isPresented: $showAddMenu, titleVisibility: .visible) {
            Button("タスクを追加") {
                guard let date = pendingAddDate else { return }
                viewModel.selectedDate = date
                newItemDate = date
                showTaskEditor = true
            }
            Button("予定を追加") {
                guard let date = pendingAddDate else { return }
                viewModel.selectedDate = date
                newItemDate = date
                showEventEditor = true
            }
            Button("キャンセル", role: .cancel) { pendingAddDate = nil }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button(action: { viewModel.stepBackward(displayMode: viewModel.displayMode) }) {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(headerTitle)
                .font(.headline)
            Spacer()
            if viewModel.selectedDate.startOfDay != Date().startOfDay {
                Button("今日へ") {
                    viewModel.jumpToToday()
                }
                .font(.caption)
            }
            Button(action: { viewModel.stepForward(displayMode: viewModel.displayMode) }) {
                Image(systemName: "chevron.right")
            }
        }
    }

    private var modePicker: some View {
        Picker("表示切替", selection: $viewModel.displayMode) {
            ForEach(JournalViewModel.DisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var headerTitle: String {
        if viewModel.displayMode == .month {
            return viewModel.monthTitle
        } else {
            guard let first = viewModel.weekDates.first,
                  let last = viewModel.weekDates.last else {
                return viewModel.monthTitle
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
        }
    }

    private var calendarSwitcher: some View {
        Group {
            if viewModel.displayMode == .month {
                monthCalendar
            } else {
                weekCalendar
            }
        }
    }

    private var monthCalendar: some View {
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.days) { day in
                VStack(spacing: 6) {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(.body)
                        .foregroundStyle(day.isWithinDisplayedMonth ? .primary : .secondary)
                    indicatorRow(events: eventCount(on: day.date),
                                 tasks: taskCount(on: day.date))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(viewModel.selectedDate.isSameDay(as: day.date) ? Color.accentColor : .clear, lineWidth: 2)
                )
                .background(
                    day.isToday ? Color.accentColor.opacity(0.08) : Color.clear
                )
                .onTapGesture {
                    viewModel.selectedDate = day.date
                }
                .onTapGesture(count: 2) {
                    handleDoubleTap(on: day.date)
                }
            }
        }
    }

    private var weekCalendar: some View {
        HStack(spacing: 12) {
            ForEach(viewModel.weekDates, id: \.self) { date in
                VStack(spacing: 6) {
                    Text(date.jaMonthDayString)
                        .font(.caption)
                    Text(date.jaWeekdayNarrowString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(summaryLabel(for: date, limit: 2))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(date.startOfDay == viewModel.selectedDate.startOfDay ? Color.accentColor : .clear, lineWidth: 2)
                )
                .onTapGesture {
                    viewModel.selectedDate = date
                }
                .onTapGesture(count: 2) {
                    handleDoubleTap(on: date)
                }
            }
        }
    }

    private var contentArea: some View {
        VStack(spacing: 12) {
            if viewModel.displayMode == .month {
                daySummary
            } else {
                weeklyTimeline
                weekDayDetail
            }
        }
    }

    private var daySummary: some View {
        let date = viewModel.selectedDate
        return SectionCard(title: date.formatted(.dateTime.year().month().day())) {
            dayDetailContent(for: date, includeAddButtons: true)
        }
    }

    // 週表示仕様: docs/requirements.md 4.5 + docs/ui-guidelines.md (Journal)
    private var weeklyTimeline: some View {
        SectionCard(title: "週のタイムライン") {
            let timelineHeight: CGFloat = 220
            let headerHeight: CGFloat = 40
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    TimelineAxisColumn(headerHeight: headerHeight,
                                       timelineHeight: timelineHeight)
                    ForEach(viewModel.weekDates, id: \.self) { date in
                        TimelineColumnView(date: date,
                                           items: viewModel.timelineItems(for: date),
                                           isSelected: date.startOfDay == viewModel.selectedDate.startOfDay,
                                           timelineHeight: timelineHeight)
                        .frame(width: 96)
                        .onTapGesture {
                            viewModel.selectedDate = date
                        }
                        .onTapGesture(count: 2) {
                            handleDoubleTap(on: date)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .frame(height: timelineHeight + headerHeight + 8)
            Text("※タイムライン上の日付をダブルタップすると予定やタスクを追加できます。スワイプでシームレスに移動できます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var weekDayDetail: some View {
        SectionCard(title: "\(viewModel.selectedDate.formatted(.dateTime.weekday(.wide))) の概要") {
            dayDetailContent(for: viewModel.selectedDate, includeAddButtons: false)
        }
    }

    @ViewBuilder
    private func dayDetailContent(for date: Date, includeAddButtons: Bool) -> some View {
        let diary = store.entry(for: date)
        let tasks = viewModel.tasks(on: date)
        let habits = store.habitRecords.filter { $0.date.isSameDay(as: date) }
        let events = store.events(on: date)
        let health = store.healthSummaries.first { $0.date.isSameDay(as: date) }

        VStack(alignment: .leading, spacing: 8) {
            if tasks.isEmpty && events.isEmpty && (diary?.text.isEmpty ?? true) && habits.isEmpty {
                Text("この日の記録はまだありません。")
                    .foregroundStyle(.secondary)
            }

            Text("タスク")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if tasks.isEmpty {
                Text("登録されたタスクはありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(task.title)
                                .font(.body.weight(.semibold))
                            Spacer()
                            if let start = task.startDate {
                                Text("開始 \(start.formattedTime())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let end = task.endDate {
                                Text("終了 \(end.formattedTime())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if task.detail.isEmpty == false {
                            Text(task.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            editingTask = task
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("日記")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let entry = diary, entry.text.isEmpty == false {
                Text(entry.text)
                if let condition = entry.conditionScore {
                    Text("体調: \(conditionLabel(for: condition))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let location = entry.locationName {
                    Text("場所: \(location)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("この日はまだ記録がありません")
                    .foregroundStyle(.secondary)
            }
            Divider()

            Text("習慣")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if habits.isEmpty {
                Text("チェック済みの習慣はありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(habits) { record in
                    if let habit = store.habits.first(where: { $0.id == record.habitID }) {
                        HStack {
                            Label(habit.title, systemImage: habit.iconName)
                            Spacer()
                            Image(systemName: record.isCompleted ? "checkmark.circle.fill" : "circle")
                        }
                        .foregroundStyle(record.isCompleted ? Color(hex: habit.colorHex) ?? .accentColor : .secondary)
                    }
                }
            }
            Divider()

            Text("予定")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if events.isEmpty {
                Text("予定はありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.body.weight(.medium))
                        Text("\(event.startDate.formattedTime()) - \(event.endDate.formattedTime()) · \(event.calendarName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingEvent = event }
                }
            }
            if events.isEmpty == false {
                Divider()
            }

            Text("ヘルス")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let health {
                let sleep = String(format: "%.1f", health.sleepHours ?? 0)
                Text("歩数 \(health.steps ?? 0)・睡眠 \(sleep)h")
            } else {
                Text("ヘルスデータなし")
                    .foregroundStyle(.secondary)
            }

            if includeAddButtons {
                HStack {
                    Button {
                        newItemDate = date
                        showTaskEditor = true
                    } label: {
                        Label("タスク追加", systemImage: "checkmark.circle.badge.plus")
                    }
                    Spacer()
                    Button {
                        newItemDate = date
                        showEventEditor = true
                    } label: {
                        Label("予定追加", systemImage: "calendar.badge.plus")
                    }
                }
                .font(.caption)
            }
        }
    }

    private func handleDoubleTap(on date: Date) {
        viewModel.selectedDate = date
        pendingAddDate = date
        showAddMenu = true
    }

    private func summaryLabel(for date: Date, limit: Int) -> String {
        let eventTitles = store.events(on: date).map(\.title)
        let taskTitles = viewModel.tasks(on: date).map(\.title)
        let combined = eventTitles + taskTitles
        guard combined.isEmpty == false else { return "" }
        let primary = combined.prefix(limit).joined(separator: " / ")
        let remainder = combined.count - limit
        if remainder > 0 {
            return "\(primary) +\(remainder)"
        }
        return primary
    }

    private func eventCount(on date: Date) -> Int {
        store.events(on: date).count
    }

    private func taskCount(on date: Date) -> Int {
        viewModel.tasks(on: date).count
    }

    @ViewBuilder
    private func indicatorRow(events: Int, tasks: Int) -> some View {
        if events == 0 && tasks == 0 {
            Circle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 8, height: 8)
        } else {
            HStack(spacing: 4) {
                if events > 0 {
                    indicator(color: .accentColor, count: events)
                }
                if tasks > 0 {
                    indicator(color: .yellow, count: tasks)
                }
            }
        }
    }

    private func indicator(color: Color, count: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 10, height: 10)
            if count > 1 {
                Text(count > 9 ? "9+" : "\(count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .offset(x: 8, y: -6)
            }
        }
        .frame(width: 18, height: 18, alignment: .center)
    }

    private func conditionLabel(for score: Int) -> String {
        let emoji: String
        switch score {
        case 5: emoji = "😄"
        case 4: emoji = "🙂"
        case 3: emoji = "😐"
        case 2: emoji = "😟"
        default: emoji = "😫"
        }
        return "\(emoji) \(score)"
    }
}

private struct TimelineAxisColumn: View {
    var headerHeight: CGFloat
    var timelineHeight: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            Color.clear
                .frame(height: headerHeight)
            TimelineAxisView(height: timelineHeight)
        }
        .frame(width: 56)
    }
}

private struct TimelineAxisView: View {
    var height: CGFloat
    private let startHour: Double = 6
    private let endHour: Double = 24
    private let step: Double = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: startHour, through: endHour, by: step)), id: \.self) { hour in
                Text(String(format: "%02.0f:00", hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: yOffset(for: hour))
            }
        }
        .frame(width: 50, height: height)
    }

    private func yOffset(for hour: Double) -> CGFloat {
        let ratio = CGFloat((hour - startHour) / (endHour - startHour))
        return max(0, min(1, ratio)) * height - 6
    }
}

private struct TimelineColumnView: View {
    var date: Date
    var items: [JournalViewModel.TimelineItem]
    var isSelected: Bool
    var timelineHeight: CGFloat

    private var dayLabel: String {
        date.jaWeekdayNarrowString
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(date.jaMonthDayString)
                .font(.caption.bold())
            Text(dayLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.08))
                    .frame(height: timelineHeight)
                ForEach(items) { item in
                    let (offset, blockHeight) = position(for: item, in: timelineHeight)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let detail = item.detail, detail.isEmpty == false {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(item.kind == .event ? Color.blue : Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(height: blockHeight, alignment: .top)
                    .offset(y: offset)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func position(for item: JournalViewModel.TimelineItem, in contentHeight: CGFloat) -> (CGFloat, CGFloat) {
        let startHour = hourValue(for: item.start)
        var endHour = hourValue(for: item.end)
        var normalizedStart = max(startHour - 6, 0)
        var normalizedEnd = max(endHour - 6, 0)
        if normalizedEnd < normalizedStart {
            normalizedEnd += 24
        }
        let totalHours: Double = 18
        normalizedStart = min(normalizedStart, totalHours)
        normalizedEnd = min(normalizedEnd, totalHours + 6)
        let offset = CGFloat(normalizedStart / totalHours) * contentHeight
        let height = CGFloat(max((normalizedEnd - normalizedStart) / totalHours, 0.05)) * contentHeight
        return (offset, height)
    }

    private func hourValue(for date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
    }
}
