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
    private let monthPagerHeight: CGFloat = 640
    private let monthPagerRadius = 18
    @State private var monthPagerAnchors: [Date] = []
    @State private var monthPagerSelection: Int = 0
    @State private var isSyncingMonthPager = false
    private let weekPagerHeight: CGFloat = 460
    private let weekPagerRadius = 52
    @State private var weekPagerAnchors: [Date] = []
    @State private var weekPagerSelection: Int = 0
    @State private var isSyncingWeekPager = false
    @State private var showTaskEditor = false
    @State private var showEventEditor = false
    @State private var editingEvent: CalendarEvent?
    @State private var editingTask: Task?
    @State private var showAddMenu = false
    @State private var pendingAddDate: Date?
    @State private var newItemDate: Date?
    @State private var todayAnimationDuration: Double?
    @State private var isProgrammaticWeekPagerChange = false
    @Namespace private var selectionNamespace

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
        .onAppear {
            prepareMonthPagerIfNeeded()
            prepareWeekPagerIfNeeded()
            viewModel.preloadMonths(around: viewModel.monthAnchor, radius: 1)
        }
        .onChange(of: viewModel.displayMode) { mode in
            if mode == .week {
                ensureWeekPagerIncludes(date: viewModel.selectedDate)
            } else {
                ensureMonthPagerIncludes(date: viewModel.selectedDate)
            }
        }
        .onChange(of: viewModel.selectedDate) { newValue in
            if viewModel.displayMode == .week, isSyncingWeekPager == false {
                ensureWeekPagerIncludes(date: newValue)
            } else if viewModel.displayMode == .month, isSyncingMonthPager == false {
                ensureMonthPagerIncludes(date: newValue)
            }
        }
        .onChange(of: viewModel.monthAnchor) { newAnchor in
            guard viewModel.displayMode == .month else { return }
            ensureMonthPagerIncludes(date: newAnchor)
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
                    let today = Date().startOfDay
                    let calendar = Calendar.current
                    let longDuration = 0.55
                    let shortDuration = 0.25
                    let needsLongAnimation: Bool
                    switch viewModel.displayMode {
                    case .month:
                        needsLongAnimation = calendar.isDate(viewModel.monthAnchor, equalTo: today, toGranularity: .month) == false
                    case .week:
                        needsLongAnimation = calendar.isDate(viewModel.selectedDate, equalTo: today, toGranularity: .weekOfYear) == false
                    }
                    let duration = needsLongAnimation ? longDuration : shortDuration
                    todayAnimationDuration = duration
                    withAnimation(.easeInOut(duration: duration)) {
                        viewModel.jumpToToday()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        todayAnimationDuration = nil
                    }
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
                monthPager
            }
        }
    }

    private var monthPager: some View {
        TabView(selection: $monthPagerSelection) {
            ForEach(Array(monthPagerAnchors.enumerated()), id: \.offset) { index, anchor in
                VStack(spacing: 0) {
                    monthCalendar(for: anchor)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .padding(.horizontal, 4)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: monthPagerHeight, alignment: .top)
        .onChange(of: monthPagerSelection) { newValue in
            guard monthPagerAnchors.indices.contains(newValue) else { return }
            let anchor = monthPagerAnchors[newValue]
            let calendar = Calendar.current
            if calendar.isDate(anchor, equalTo: viewModel.monthAnchor, toGranularity: .month) == false {
                isSyncingMonthPager = true
                let duration = todayAnimationDuration ?? 0.18
                withAnimation(.easeInOut(duration: duration)) {
                    viewModel.selectedDate = anchor
                }
                viewModel.alignAnchorIfNeeded(for: .month)
                DispatchQueue.main.async { self.isSyncingMonthPager = false }
            }
            extendMonthPagerIfNeeded(at: newValue)
        }
    }

    private func monthCalendar(for anchor: Date) -> some View {
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        let days = viewModel.calendarDays(for: anchor)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(.body)
                        .foregroundStyle(day.isWithinDisplayedMonth ? .primary : .secondary)
                    indicatorRow(events: eventCount(on: day.date),
                                 tasks: taskCount(on: day.date))
                    wellnessRow(for: day.date)
                }
                .frame(maxWidth: .infinity)
                .frame(minWidth: 42, idealWidth: 44)
                .frame(minHeight: 90)
                .padding(.top, 0)
                .padding(.bottom, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(day.isToday ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.clear, lineWidth: 2)
                )
                .overlay(alignment: .center) {
                    if viewModel.selectedDate.isSameDay(as: day.date) {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .matchedGeometryEffect(id: "calendar-selection", in: selectionNamespace)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.06)) {
                        viewModel.selectedDate = day.date
                    }
                }
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    handleDoubleTap(on: day.date)
                })
            }
        }
        .animation(.easeInOut(duration: 0.55), value: viewModel.selectedDate)
    }

    private var contentArea: some View {
        VStack(spacing: 12) {
            if viewModel.displayMode == .month {
                daySummary
            } else {
                weekPager
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
    private var weekPager: some View {
        TabView(selection: $weekPagerSelection) {
            ForEach(Array(weekPagerAnchors.enumerated()), id: \.offset) { index, anchor in
                VStack(spacing: 12) {
                    weekCalendar(for: anchor)
                    weekTimeline(for: anchor)
                }
                .padding(.top, 24)
                .padding(.bottom, 8)
                .padding(.horizontal, 4)
                .frame(maxHeight: .infinity, alignment: .top)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: weekPagerHeight)
        .onChange(of: weekPagerSelection) { newValue in
            guard weekPagerAnchors.indices.contains(newValue) else { return }
            let anchor = weekPagerAnchors[newValue]
            if isProgrammaticWeekPagerChange {
                isProgrammaticWeekPagerChange = false
            } else if Calendar.current.isDate(anchor, inSameDayAs: viewModel.selectedDate) == false {
                isSyncingWeekPager = true
                let duration = todayAnimationDuration ?? 0.18
                withAnimation(.easeInOut(duration: duration)) {
                    viewModel.selectedDate = anchor
                }
                DispatchQueue.main.async { self.isSyncingWeekPager = false }
            }
            extendWeekPagerIfNeeded(at: newValue)
        }
    }

    private func extendWeekPagerIfNeeded(at index: Int) {
        let threshold = 6
        if index <= threshold {
            prependWeekAnchors(count: threshold)
        } else if index >= weekPagerAnchors.count - threshold - 1 {
            appendWeekAnchors(count: threshold)
        }
    }

    private func prependWeekAnchors(count: Int) {
        guard let first = weekPagerAnchors.first else { return }
        let calendar = Calendar.current
        let start = weekStart(for: first)
        var newDates: [Date] = []
        for step in 1...count {
            if let newDate = calendar.date(byAdding: .weekOfYear, value: -step, to: start) {
                newDates.insert(newDate, at: 0)
            }
        }
        if newDates.isEmpty { return }
        weekPagerAnchors.insert(contentsOf: newDates, at: 0)
        weekPagerSelection += newDates.count
    }

    private func appendWeekAnchors(count: Int) {
        guard let last = weekPagerAnchors.last else { return }
        let calendar = Calendar.current
        let start = weekStart(for: last)
        for step in 1...count {
            if let newDate = calendar.date(byAdding: .weekOfYear, value: step, to: start) {
                weekPagerAnchors.append(newDate)
            }
        }
    }

    private func weekStart(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }

    private var weekDayDetail: some View {
        SectionCard(title: "\(viewModel.selectedDate.formatted(.dateTime.weekday(.wide))) の概要") {
            dayDetailContent(for: viewModel.selectedDate, includeAddButtons: false)
        }
    }

    private func weekCalendar(for anchor: Date) -> some View {
        let dates = weekDates(for: anchor)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(dates, id: \.self) { date in
                VStack(spacing: 6) {
                    Text("\(Calendar.current.component(.day, from: date))日")
                        .font(.caption)
                    Text(date.jaWeekdayNarrowString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    indicatorRow(events: eventCount(on: date),
                                 tasks: taskCount(on: date))
                    wellnessRow(for: date)
                }
                .frame(maxWidth: .infinity)
                .frame(minWidth: 42, idealWidth: 44)
                .frame(minHeight: 90)
                .padding(.top, 0)
                .padding(.bottom, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(date.isSameDay(as: Date()) ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.clear, lineWidth: 2)
                )
                .overlay(alignment: .center) {
                    if date.startOfDay == viewModel.selectedDate.startOfDay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .matchedGeometryEffect(id: "calendar-selection", in: selectionNamespace)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.06)) {
                        viewModel.selectedDate = date
                    }
                }
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    handleDoubleTap(on: date)
                })
            }
        }
        .animation(.easeInOut(duration: 0.55), value: viewModel.selectedDate)
    }

    private func weekTimeline(for anchor: Date) -> some View {
        let timelineHeight: CGFloat = 220
        let headerHeight: CGFloat = 40
        let dates = weekDates(for: anchor)
        return SectionCard(title: "週のタイムライン") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    TimelineAxisColumn(headerHeight: headerHeight,
                                       timelineHeight: timelineHeight)
                    ForEach(dates, id: \.self) { date in
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

    @ViewBuilder
    private func wellnessRow(for date: Date) -> some View {
        let sleep = sleepHours(on: date)
        let steps = stepsCount(on: date)
        let diary = hasDiaryEntry(on: date)

        if sleep == nil && steps == nil && diary == false {
            Color.clear.frame(height: 16)
        } else {
            HStack(spacing: 2) {
                if let hours = sleep {
                    wellnessEmoji("🛌", isActive: hours >= 8)
                }
                if let step = steps {
                    wellnessEmoji("👣", isActive: step >= 10_000)
                }
                if diary {
                    wellnessEmoji("📔", isActive: true)
                }
            }
            .frame(height: 16, alignment: .center)
        }
    }

    @ViewBuilder
    private func weekDates(for anchor: Date) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)) ?? anchor
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func prepareMonthPagerIfNeeded() {
        if monthPagerAnchors.isEmpty {
            regenerateMonthPager(centeredAt: viewModel.monthAnchor)
        }
    }

    private func regenerateMonthPager(centeredAt date: Date) {
        isSyncingMonthPager = true
        let start = monthStart(for: date)
        let calendar = Calendar.current
        let offsets = Array(-monthPagerRadius...monthPagerRadius)
        monthPagerAnchors = offsets.compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
            .map { monthStart(for: $0) }
        viewModel.preloadMonths(around: start, radius: 1)
        if let index = monthPagerAnchors.firstIndex(where: { calendar.isDate($0, equalTo: start, toGranularity: .month) }) {
            applyCalendarAnimationIfNeeded {
                monthPagerSelection = index
            }
        } else {
            applyCalendarAnimationIfNeeded {
                monthPagerSelection = monthPagerRadius
            }
        }
        DispatchQueue.main.async {
            self.isSyncingMonthPager = false
        }
    }

    private func ensureMonthPagerIncludes(date: Date) {
        let calendar = Calendar.current
        let start = monthStart(for: date)
        if let index = monthPagerAnchors.firstIndex(where: { calendar.isDate($0, equalTo: start, toGranularity: .month) }) {
            applyCalendarAnimationIfNeeded {
                monthPagerSelection = index
            }
        } else {
            regenerateMonthPager(centeredAt: start)
        }
        viewModel.preloadMonths(around: start, radius: 1)
    }

    private func extendMonthPagerIfNeeded(at index: Int) {
        let threshold = 3
        if index <= threshold {
            prependMonthAnchors(count: threshold)
        } else if index >= monthPagerAnchors.count - threshold - 1 {
            appendMonthAnchors(count: threshold)
        }
    }

    private func prependMonthAnchors(count: Int) {
        guard let first = monthPagerAnchors.first else { return }
        let calendar = Calendar.current
        let start = monthStart(for: first)
        var newDates: [Date] = []
        for step in 1...count {
            if let newDate = calendar.date(byAdding: .month, value: -step, to: start) {
                newDates.insert(monthStart(for: newDate), at: 0)
            }
        }
        guard newDates.isEmpty == false else { return }
        monthPagerAnchors.insert(contentsOf: newDates, at: 0)
        monthPagerSelection += newDates.count
        newDates.forEach { viewModel.preloadMonths(around: $0, radius: 0) }
    }

    private func appendMonthAnchors(count: Int) {
        guard let last = monthPagerAnchors.last else { return }
        let calendar = Calendar.current
        let start = monthStart(for: last)
        for step in 1...count {
            if let newDate = calendar.date(byAdding: .month, value: step, to: start) {
                let monthStartDate = monthStart(for: newDate)
                monthPagerAnchors.append(monthStartDate)
                viewModel.preloadMonths(around: monthStartDate, radius: 0)
            }
        }
    }

    private func monthStart(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func prepareWeekPagerIfNeeded() {
        if weekPagerAnchors.isEmpty {
            regenerateWeekPager(centeredAt: viewModel.selectedDate)
        }
    }

    private func regenerateWeekPager(centeredAt date: Date) {
        isSyncingWeekPager = true
        let start = weekStart(for: date)
        let calendar = Calendar.current
        let offsets = Array(-weekPagerRadius...weekPagerRadius)
        weekPagerAnchors = offsets.compactMap { calendar.date(byAdding: .weekOfYear, value: $0, to: start) }
        let target = weekPagerAnchors.firstIndex(where: { calendar.isDate($0, inSameDayAs: start) }) ?? weekPagerRadius
        setWeekPagerSelection(target)
        DispatchQueue.main.async {
            self.isSyncingWeekPager = false
        }
    }

    private func ensureWeekPagerIncludes(date: Date) {
        let calendar = Calendar.current
        let start = weekStart(for: date)
        if let index = weekPagerAnchors.firstIndex(where: { calendar.isDate($0, inSameDayAs: start) }) {
            setWeekPagerSelection(index)
        } else {
            regenerateWeekPager(centeredAt: start)
        }
    }

    @ViewBuilder
    private func indicatorRow(events: Int, tasks: Int) -> some View {
        if events == 0 && tasks == 0 {
            Color.clear.frame(height: 16)
        } else {
            HStack(spacing: 6) {
                if events > 0 {
                    dotIndicator(color: .accentColor, count: events)
                }
                if tasks > 0 {
                    dotIndicator(color: .yellow, count: tasks)
                }
            }
            .frame(height: 16, alignment: .center)
        }
    }

    private func dotIndicator(color: Color, count: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(color.opacity(0.85))
                .frame(width: 10, height: 10)
            if count > 1 {
                Text(count > 9 ? "9+" : "\(count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .offset(x: 8, y: -6)
            }
        }
        .frame(width: 18, height: 18)
    }

    private func wellnessEmoji(_ symbol: String, isActive: Bool) -> some View {
        Text(symbol)
            .font(.system(size: 9))
            .opacity(isActive ? 1 : 0.25)
    }

    private func hasDiaryEntry(on date: Date) -> Bool {
        if let entry = store.entry(for: date) {
            return entry.text.isEmpty == false || entry.photoPaths.isEmpty == false || entry.mood != nil || entry.conditionScore != nil
        }
        return false
    }

    private func sleepHours(on date: Date) -> Double? {
        guard let summary = store.healthSummaries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }),
              let hours = summary.sleepHours, hours > 0 else {
            return nil
        }
        return hours
    }

    private func stepsCount(on date: Date) -> Int? {
        guard let summary = store.healthSummaries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }),
              let steps = summary.steps, steps > 0 else {
            return nil
        }
        return steps
    }

    private func eventCount(on date: Date) -> Int {
        store.events(on: date).count
    }

    private func taskCount(on date: Date) -> Int {
        viewModel.tasks(on: date).count
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

    private func setWeekPagerSelection(_ index: Int) {
        isProgrammaticWeekPagerChange = true
        applyCalendarAnimationIfNeeded {
            weekPagerSelection = index
        }
    }

    private func applyCalendarAnimationIfNeeded(_ updates: @escaping () -> Void) {
        if let duration = todayAnimationDuration {
            withAnimation(.easeInOut(duration: duration), updates)
        } else {
            updates()
        }
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
