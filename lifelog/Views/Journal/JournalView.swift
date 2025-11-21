//
//  JournalView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct JournalView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let store: AppDataStore
    @StateObject private var viewModel: JournalViewModel
    private let monthPagerHeight: CGFloat = 560
    @State private var detailPanelHeight: CGFloat = 520
    private let monthPagerRadius = 6
    @State private var monthPagerAnchors: [Date] = []
    @State private var monthPagerSelection: Int = 0
    @State private var isSyncingMonthPager = false
    private let weekPagerHeight: CGFloat = 780
    private let weekPagerRadius = 52
    @State private var weekPagerAnchors: [Date] = []
    @State private var weekPagerSelection: Int = 0
    @State private var isSyncingWeekPager = false
    @State private var showTaskEditor = false
    @State private var showEventEditor = false
    @State private var showDiaryEditor = false
    @State private var editingEvent: CalendarEvent?
    @State private var editingTask: Task?
    @State private var tappedTimelineItem: JournalViewModel.TimelineItem?
    @State private var showAddMenu = false
    @State private var pendingAddDate: Date?
    @State private var newItemDate: Date?
    @State private var diaryEditorDate: Date = Date()
    @State private var isProgrammaticWeekPagerChange = false
    private let detailPagerRadius = 14
    @State private var detailPagerAnchors: [Date] = []
    @State private var detailPagerSelection: Int = 0
    @State private var isSyncingDetailPager = false
    @State private var detailHeights: [Int: CGFloat] = [:]
    @Namespace private var selectionNamespace
    @State private var scrollProxy: ScrollViewProxy?

    init(store: AppDataStore) {
        self.store = store
        _viewModel = StateObject(wrappedValue: JournalViewModel(store: store))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    modePicker
                    if viewModel.displayMode == .month {
                        weekdayHeader
                            .padding(.horizontal, 4)
                    } else if viewModel.displayMode == .week {
                        weekdayHeader
                            .padding(.horizontal, 4)
                    }
                    calendarSwitcher
                    contentArea
                }
                .padding()
            }
            .onAppear { scrollProxy = proxy }
            .popover(item: $tappedTimelineItem) { item in
                TimelineItemDetailView(item: item) {
                    // Dismiss popover first
                    tappedTimelineItem = nil
                    // Then trigger the edit sheet after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        handleEdit(for: item)
                    }
                }
            }
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
        .sheet(isPresented: $showDiaryEditor) {
            NavigationStack {
                DiaryEditorView(store: store, date: diaryEditorDate)
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
            prepareDetailPagerIfNeeded()
            viewModel.preloadMonths(around: viewModel.monthAnchor, radius: 1)
        }
        .onChange(of: viewModel.displayMode) { _, newMode in
            if newMode == .week {
                ensureWeekPagerIncludes(date: viewModel.selectedDate)
            } else {
                ensureMonthPagerIncludes(date: viewModel.selectedDate)
            }
            ensureDetailPagerIncludes(date: viewModel.selectedDate)
        }
        .onChange(of: viewModel.selectedDate) { _, newDate in
            if viewModel.displayMode == .week, isSyncingWeekPager == false {
                ensureWeekPagerIncludes(date: newDate)
            } else if viewModel.displayMode == .month, isSyncingMonthPager == false {
                ensureMonthPagerIncludes(date: newDate)
            }
            if isSyncingDetailPager == false {
                ensureDetailPagerIncludes(date: newDate)
            } else {
                isSyncingDetailPager = false
            }
        }
        .onChange(of: viewModel.monthAnchor) { _, newAnchor in
            guard viewModel.displayMode == .month else { return }
            ensureMonthPagerIncludes(date: newAnchor)
        }
    }

    private func handleEdit(for item: JournalViewModel.TimelineItem) {
        switch item.kind {
        case .event:
            guard let id = item.sourceId,
                  let event = store.calendarEvents.first(where: { $0.id == id }) else { return }
            editingEvent = event
        case .task:
             guard let id = item.sourceId,
                   let task = store.tasks.first(where: { $0.id == id }) else { return }
             editingTask = task
        case .sleep:
            // No edit action for sleep items
            break
        }
    }

    private var shouldShowTodayButton: Bool {
        let today = Date().startOfDay
        let calendar = Calendar.current
        if calendar.isDate(viewModel.selectedDate, inSameDayAs: today) == false {
            return true
        }
        switch viewModel.displayMode {
        case .month:
            return !calendar.isDate(viewModel.monthAnchor, equalTo: today, toGranularity: .month)
        case .week:
            guard weekPagerAnchors.indices.contains(weekPagerSelection) else { return false }
            let currentWeekAnchor = weekPagerAnchors[weekPagerSelection]
            return !calendar.isDate(currentWeekAnchor, equalTo: today, toGranularity: .weekOfYear)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.4)) {
                    viewModel.stepBackward(displayMode: viewModel.displayMode)
                }
            }) {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(headerTitle)
                .font(.headline)
            Spacer()
            if shouldShowTodayButton {
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
                    withAnimation(.easeInOut(duration: duration)) {
                        viewModel.jumpToToday()
                        ensureMonthPagerIncludes(date: today)
                        ensureWeekPagerIncludes(date: today)
                        ensureDetailPagerIncludes(date: today)
                    }
                }
                .font(.caption)
            }
            Button(action: {
                withAnimation(.easeInOut(duration: 0.4)) {
                    viewModel.stepForward(displayMode: viewModel.displayMode)
                }
            }) {
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
            return "\(first.jaMonthDayString) - \(last.jaMonthDayString)"
        }
    }

    private var weekdayHeader: some View {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ja_JP")
        let weekdays = calendar.shortWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { weekday in
                Text(weekday)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
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
        .onChange(of: monthPagerSelection) { _, newSelection in
            guard monthPagerAnchors.indices.contains(newSelection) else { return }
            let anchor = monthPagerAnchors[newSelection]
            let calendar = Calendar.current
            if calendar.isDate(anchor, equalTo: viewModel.monthAnchor, toGranularity: .month) == false {
                isSyncingMonthPager = true
                viewModel.setMonthAnchor(anchor)
                DispatchQueue.main.async { self.isSyncingMonthPager = false }
            }
            extendMonthPagerIfNeeded(at: newSelection)
        }
    }

    private func monthCalendar(for anchor: Date) -> some View {
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        let days = viewModel.calendarDays(for: anchor)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(.body)
                        .foregroundStyle(day.isWithinDisplayedMonth ? .primary : .secondary)
                    indicatorRow(events: eventCount(on: day.date),
                                 tasks: taskCount(on: day.date))
                    wellnessRow(for: day.date)
                }
                .frame(maxWidth: .infinity)
                .frame(minWidth: 36, idealWidth: 38)
                .frame(minHeight: 70)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
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
                            .matchedGeometryEffect(id: "calendar-selection",
                                                   in: selectionNamespace,
                                                   isSource: viewModel.displayMode == .month)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.selectedDate.isSameDay(as: day.date) {
                        scrollToDetailPanel()
                    } else {
                        viewModel.selectedDate = day.date
                    }
                }
            }
        }
        .animation(.easeInOut, value: viewModel.selectedDate)
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
        detailPager(includeAddButtons: true)
    }

    // 週表示仕様: docs/requirements.md 4.5 + docs/ui-guidelines.md (Journal)
    private var weekPager: some View {
        TabView(selection: $weekPagerSelection) {
            ForEach(Array(weekPagerAnchors.enumerated()), id: \.offset) { index, anchor in
                VStack(spacing: 12) {
                    weekCalendar(for: anchor)
                        .padding(.top, 4)
                    weekTimeline(for: anchor)
                }
                .padding(.bottom, 8)
                .padding(.horizontal, 4)
                .frame(maxHeight: .infinity, alignment: .top)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: weekPagerHeight)
        .onChange(of: weekPagerSelection) { _, newSelection in
            guard weekPagerAnchors.indices.contains(newSelection) else { return }
            let anchor = weekPagerAnchors[newSelection]
            if isProgrammaticWeekPagerChange {
                isProgrammaticWeekPagerChange = false
            } else if Calendar.current.isDate(anchor, inSameDayAs: viewModel.selectedDate) == false {
                // Do nothing to keep the selected date
            }
            extendWeekPagerIfNeeded(at: newSelection)
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
        detailPager(includeAddButtons: false)
    }

    private func weekCalendar(for anchor: Date) -> some View {
        let dates = weekDates(for: anchor)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(dates, id: \.self) { date in
                VStack(spacing: 4) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.body)
                    indicatorRow(events: eventCount(on: date),
                                 tasks: taskCount(on: date))
                    wellnessRow(for: date)
                }
                .frame(maxWidth: .infinity)
                .frame(minWidth: 36, idealWidth: 38)
                .frame(minHeight: 70)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
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
                            .matchedGeometryEffect(id: "calendar-selection",
                                                   in: selectionNamespace,
                                                   isSource: viewModel.displayMode == .week)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.selectedDate.isSameDay(as: date) {
                        scrollToDetailPanel()
                    } else {
                        viewModel.selectedDate = date
                    }
                }
            }
        }
        .animation(.easeInOut, value: viewModel.selectedDate)
    }

    private func weekTimeline(for anchor: Date) -> some View {
        let timelineHeight: CGFloat = 520
        let dates = weekDates(for: anchor)

        return SectionCard(title: "週のタイムライン") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(dates, id: \.self) { date in
                        TimelineColumnView(
                            date: date,
                            items: viewModel.timelineItems(for: date).filter { $0.kind != .task },
                            isSelected: date.startOfDay == viewModel.selectedDate.startOfDay,
                            timelineHeight: timelineHeight,
                            onTapItem: { item in
                                tappedTimelineItem = item
                            },
                            onLongPressItem: { item in
                                handleEdit(for: item)
                            }
                        )
                        .frame(width: 108)
                        .onTapGesture {
                            viewModel.selectedDate = date
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .frame(height: timelineHeight + 16)
        }
    }

    private func toggleTask(_ task: Task) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            store.toggleTaskCompletion(task.id)
        }
    }

    private func toggleHabit(_ habit: Habit, on date: Date) {
        store.toggleHabit(habit.id, on: date)
    }

    private func openDiaryEditor(for date: Date) {
        diaryEditorDate = date
        showDiaryEditor = true
    }

    private func handleQuickAction(on date: Date) {
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

    private func weekDates(for anchor: Date) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)) ?? anchor
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func calendarSnapshot(for date: Date) -> CalendarDetailSnapshot {
        let events = store.events(on: date)
        let sortedTasks = viewModel.tasks(on: date).sorted(by: calendarTaskSort)
        let pendingTasks = sortedTasks.filter { $0.isCompleted == false }
        let completedTasks = sortedTasks.filter(\.isCompleted)
        let statuses = store.habits
            .filter { $0.schedule.isActive(on: date) }
            .map { habit in
                TodayViewModel.DailyHabitStatus(habit: habit,
                                                record: store.habitRecords.first {
                                                    $0.habitID == habit.id && Calendar.current.isDate($0.date, inSameDayAs: date)
                                                })
            }
        let health = store.healthSummaries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        let diary = store.entry(for: date)
        return CalendarDetailSnapshot(date: date,
                                      events: events,
                                      pendingTasks: pendingTasks,
                                      completedTasks: completedTasks,
                                      habitStatuses: statuses,
                                      healthSummary: health,
                                      diaryEntry: diary)
    }

    private func calendarTaskSort(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        let lhsDate = taskDisplayDate(for: lhs) ?? .distantFuture
        let rhsDate = taskDisplayDate(for: rhs) ?? .distantFuture
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.title < rhs.title
    }

    private func taskDisplayDate(for task: Task) -> Date? {
        task.startDate ?? task.endDate
    }

    private func detailPager(includeAddButtons: Bool) -> some View {
        SectionCard(title: "選択中の日") {
            TabView(selection: $detailPagerSelection) {
                ForEach(Array(detailPagerAnchors.enumerated()), id: \.offset) { index, anchor in
                    let snapshot = calendarSnapshot(for: anchor)
                    CalendarDetailPanel(snapshot: snapshot,
                                        includeAddButtons: includeAddButtons,
                                        onAddTask: {
                                            newItemDate = snapshot.date
                                            showTaskEditor = true
                                        },
                                        onAddEvent: {
                                            newItemDate = snapshot.date
                                            showEventEditor = true
                                        },
                                        onEditTask: { task in editingTask = task },
                                        onEditEvent: { event in editingEvent = event },
                                        onToggleTask: { toggleTask($0) },
                                        onToggleHabit: { toggleHabit($0, on: snapshot.date) },
                                        onOpenDiary: { openDiaryEditor(for: $0) })
                    .tag(index)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: DetailPagerHeightKey.self,
                                                   value: [index: proxy.size.height])
                        }
                    )
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity)
            .frame(height: detailPanelHeight)
            .onPreferenceChange(DetailPagerHeightKey.self) { heights in
                detailHeights.merge(heights, uniquingKeysWith: { _, new in new })
                updateDetailHeightIfNeeded(detailHeights[detailPagerSelection])
            }
            .onChange(of: detailPagerSelection) { _, newSelection in
                guard detailPagerAnchors.indices.contains(newSelection) else { return }
                let date = detailPagerAnchors[newSelection]
                if date.startOfDay != viewModel.selectedDate.startOfDay {
                    isSyncingDetailPager = true
                    viewModel.selectedDate = date
                }
                updateDetailHeightIfNeeded(detailHeights[newSelection])
                extendDetailPagerIfNeeded(at: newSelection)
            }
        }
        .id(ScrollTarget.detailPanel)
    }

    private func prepareDetailPagerIfNeeded() {
        if detailPagerAnchors.isEmpty {
            regenerateDetailPager(centeredAt: viewModel.selectedDate)
        }
    }

    private func regenerateDetailPager(centeredAt date: Date) {
        isSyncingDetailPager = true
        let start = date.startOfDay
        let calendar = Calendar.current
        let offsets = Array(-detailPagerRadius...detailPagerRadius)
        detailPagerAnchors = offsets.compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let targetIndex = detailPagerAnchors.firstIndex(where: { $0.startOfDay == start }) ?? detailPagerRadius
        setDetailPagerSelection(targetIndex, animated: false)
        DispatchQueue.main.async { self.isSyncingDetailPager = false }
    }

    private func ensureDetailPagerIncludes(date: Date) {
        let normalized = date.startOfDay
        if let index = detailPagerAnchors.firstIndex(where: { $0.startOfDay == normalized }) {
            setDetailPagerSelection(index)
        } else {
            regenerateDetailPager(centeredAt: normalized)
        }
    }

    private func extendDetailPagerIfNeeded(at index: Int) {
        let threshold = 5
        if index <= threshold {
            prependDetailAnchors(count: detailPagerRadius)
        } else if index >= detailPagerAnchors.count - threshold - 1 {
            appendDetailAnchors(count: detailPagerRadius)
        }
    }

    private func prependDetailAnchors(count: Int) {
        guard let first = detailPagerAnchors.first else { return }
        let calendar = Calendar.current
        var newDates: [Date] = []
        for step in 1...count {
            if let date = calendar.date(byAdding: .day, value: -step, to: first.startOfDay) {
                newDates.insert(date.startOfDay, at: 0)
            }
        }
        guard newDates.isEmpty == false else { return }
        detailPagerAnchors.insert(contentsOf: newDates, at: 0)
        detailPagerSelection += newDates.count
    }

    private func appendDetailAnchors(count: Int) {
        guard let last = detailPagerAnchors.last else { return }
        let calendar = Calendar.current
        for step in 1...count {
            if let date = calendar.date(byAdding: .day, value: step, to: last.startOfDay) {
                detailPagerAnchors.append(date.startOfDay)
            }
        }
    }

    private func setDetailPagerSelection(_ index: Int, animated: Bool = true) {
        guard detailPagerSelection != index else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.4)) {
                detailPagerSelection = index
            }
        } else {
            detailPagerSelection = index
        }
    }

    private func scrollToDetailPanel() {
        guard let proxy = scrollProxy else { return }
        withAnimation(.linear(duration: 0.5)) {
            proxy.scrollTo(ScrollTarget.detailPanel, anchor: .top)
        }
    }

    private func updateDetailHeightIfNeeded(_ height: CGFloat?) {
        guard let height else { return }
        let target = max(360, height + 24)
        if abs(detailPanelHeight - target) > 4 {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                detailPanelHeight = target
            }
        }
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
            monthPagerSelection = index
        } else {
            monthPagerSelection = monthPagerRadius
        }
        DispatchQueue.main.async {
            self.isSyncingMonthPager = false
        }
    }

    private func ensureMonthPagerIncludes(date: Date) {
        let calendar = Calendar.current
        let start = monthStart(for: date)
        if let index = monthPagerAnchors.firstIndex(where: { calendar.isDate($0, equalTo: start, toGranularity: .month) }) {
            monthPagerSelection = index
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
            Color.clear.frame(height: 12)
        } else {
            HStack(spacing: 4) {
                if events > 0 {
                    dotIndicator(color: .accentColor, count: events)
                }
                if tasks > 0 {
                    dotIndicator(color: .yellow, count: tasks)
                }
            }
            .frame(height: 12, alignment: .center)
        }
    }

    private func dotIndicator(color: Color, count: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(color.opacity(0.85))
                .frame(width: 8, height: 8)
            if count > 1 {
                Text(count > 9 ? "9+" : "\(count)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .offset(x: 6, y: -5)
            }
        }
        .frame(width: 14, height: 14)
    }

    private func wellnessEmoji(_ symbol: String, isActive: Bool) -> some View {
        let isDarkMode = colorScheme == .dark
        // docs/ui-guidelines.md §カレンダー: calendar emojis should stay legible, even in dark mode.
        return Text(symbol)
            .font(.system(size: 8))
            .frame(width: 10, height: 10)
            .padding(1)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isDarkMode ? Color.white.opacity(0.18) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isDarkMode ? Color.white.opacity(0.3) : Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(isDarkMode ? 0.25 : 0.08), radius: isDarkMode ? 1.5 : 0.8, x: 0, y: 0.5)
            .opacity(isActive ? 1 : 0.35)
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

    private func setWeekPagerSelection(_ index: Int) {
        isProgrammaticWeekPagerChange = true
        weekPagerSelection = index
    }
}

private struct TimelineItemDetailView: View {
    let item: JournalViewModel.TimelineItem
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.title2.bold())
                
                Text("\(item.start.formatted(date: .omitted, time: .shortened)) - \(item.end.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let detail = item.detail, detail.isEmpty == false, detail != "__completed__" {
                    Label(detail, systemImage: "tag")
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                }
            }
            
            if item.kind != .sleep {
                Button(action: onEdit) {
                    Label("編集", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .presentationDetents([.height(180)])
    }
}

private struct CalendarDetailSnapshot {
    let date: Date
    let events: [CalendarEvent]
    let pendingTasks: [Task]
    let completedTasks: [Task]
    let habitStatuses: [TodayViewModel.DailyHabitStatus]
    let healthSummary: HealthSummary?
    let diaryEntry: DiaryEntry?
}

private enum ScrollTarget: String {
    case detailPanel
}

private struct CalendarDetailPanel: View {
    let snapshot: CalendarDetailSnapshot
    var includeAddButtons: Bool
    var onAddTask: () -> Void
    var onAddEvent: () -> Void
    var onEditTask: (Task) -> Void
    var onEditEvent: (CalendarEvent) -> Void
    var onToggleTask: (Task) -> Void
    var onToggleHabit: (Habit) -> Void
    var onOpenDiary: (Date) -> Void

    private var hasDiaryEntry: Bool {
        if let entry = snapshot.diaryEntry {
            return entry.text.isEmpty == false
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            summaryRow
            OverviewSection(icon: "calendar", title: "予定") {
                if snapshot.events.isEmpty {
                    placeholder("予定はありません")
                } else {
                    VStack(spacing: 12) {
                        ForEach(snapshot.events) { event in
                            VStack(alignment: .leading, spacing: 8) {
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
                                Button {
                                    onEditEvent(event)
                                } label: {
                                    Label("予定を編集", systemImage: "square.and.pencil")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
            OverviewSection(icon: "checkmark.circle", title: "タスク") {
                if snapshot.pendingTasks.isEmpty && snapshot.completedTasks.isEmpty {
                    placeholder("登録されたタスクはありません")
                } else {
                    VStack(spacing: 16) {
                        if snapshot.pendingTasks.isEmpty == false {
                            taskGroup(title: "進行中", tasks: snapshot.pendingTasks)
                        }
                        if snapshot.completedTasks.isEmpty == false {
                            taskGroup(title: "完了済み", tasks: snapshot.completedTasks)
                        }
                    }
                }
            }
            OverviewSection(icon: "list.bullet", title: "習慣") {
                if snapshot.habitStatuses.isEmpty {
                    placeholder("この日の習慣はありません")
                } else {
                    VStack(spacing: 10) {
                        ForEach(snapshot.habitStatuses) { status in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    onToggleHabit(status.habit)
                                }
                            } label: {
                                HStack {
                                    Label(status.habit.title, systemImage: status.habit.iconName)
                                        .foregroundStyle(Color(hex: status.habit.colorHex) ?? Color.accentColor)
                                    Spacer()
                                    Image(systemName: status.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(status.isCompleted ? Color.accentColor : Color.secondary)
                                        .scaleEffect(status.isCompleted ? 1.05 : 0.95)
                                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: status.isCompleted)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            OverviewSection(icon: "heart.fill", title: "ヘルス") {
                if let summary = snapshot.healthSummary {
                    HStack(spacing: 12) {
                        StatTile(title: "歩数", value: "\(summary.steps ?? 0)")
                        StatTile(title: "睡眠", value: String(format: "%.1f h", summary.sleepHours ?? 0))
                        StatTile(title: "エネルギー", value: String(format: "%.0f kcal", summary.activeEnergy ?? 0))
                    }
                } else {
                    placeholder("ヘルスデータはありません")
                }
            }
            OverviewSection(icon: "book.closed", title: "日記") {
                VStack(alignment: .leading, spacing: 8) {
                    if let entry = snapshot.diaryEntry, entry.text.isEmpty == false {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.text)
                                .font(.body)
                            if let condition = entry.conditionScore {
                                Text("体調 \(conditionLabel(for: condition))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let location = entry.locationName {
                                Label(location, systemImage: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        placeholder("まだ日記は追加されていません")
                    }
                    Button {
                        onOpenDiary(snapshot.date)
                    } label: {
                        Label(hasDiaryEntry ? "日記を編集" : "日記を追加",
                              systemImage: "square.and.pencil")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if includeAddButtons {
                Divider()
                HStack {
                    Button(action: onAddTask) {
                        Label("タスク追加", systemImage: "checkmark.circle.badge.plus")
                    }
                    Spacer()
                    Button(action: onAddEvent) {
                        Label("予定追加", systemImage: "calendar.badge.plus")
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.date.jaYearMonthDayString)
                .font(.title3.bold())
            Text(snapshot.date.jaWeekdayWideString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            SummaryChip(icon: "calendar", label: "予定", value: snapshot.events.count, color: .blue)
            SummaryChip(icon: "checkmark.circle", label: "タスク", value: snapshot.pendingTasks.count, color: .yellow)
            SummaryChip(icon: "list.bullet", label: "習慣", value: snapshot.habitStatuses.filter(\.isCompleted).count, color: .green)
        }
    }

    private func taskGroup(title: String, tasks: [Task]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 8) {
                    TaskRowView(task: task, onToggle: { onToggleTask(task) })
                    Button {
                        onEditTask(task)
                    } label: {
                        Label("タスクを編集", systemImage: "square.and.pencil")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for category: String) -> Color {
        CategoryPalette.color(for: category)
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

private struct SummaryChip: View {
    var icon: String
    var label: String
    var value: Int
    var color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.headline.bold())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct OverviewSection<Content: View>: View {
    var icon: String
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct DetailPagerHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TimelineColumnView: View {
    var date: Date
    var items: [JournalViewModel.TimelineItem]
    var isSelected: Bool
    var timelineHeight: CGFloat
    var onTapItem: (JournalViewModel.TimelineItem) -> Void
    var onLongPressItem: (JournalViewModel.TimelineItem) -> Void

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
                    if blockHeight > 1 {
                        let threshold: CGFloat = 36
                        let alignment: Alignment = blockHeight < threshold ? .center : .top

                        RoundedRectangle(cornerRadius: 6)
                            .fill(item.kind == .sleep ? Color.purple : (item.kind == .event ? Color.blue : Color.green))
                            .frame(height: blockHeight)
                            .overlay(alignment: alignment) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading) {
                                        Text(item.title)
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        
                                        if blockHeight >= threshold { // 長い予定の場合のみ詳細を表示
                                            if let detail = item.detail, detail.isEmpty == false, detail != "__completed__" {
                                                 Text(detail)
                                                    .font(.system(size: 8))
                                                    .foregroundStyle(.white.opacity(0.9))
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing) {
                                        if blockHeight < threshold {
                                            // 短い予定: 開始時間のみ (右上)
                                            Text(item.start.formatted(date: .omitted, time: .shortened))
                                                .font(.system(size: 8))
                                                .foregroundStyle(.white.opacity(0.85))
                                        } else {
                                            // 長い予定: 開始時刻 (右上) と 終了時刻 (右下)
                                            Text(item.start.formatted(date: .omitted, time: .shortened))
                                                .font(.system(size: 8))
                                                .foregroundStyle(.white.opacity(0.85))
                                            Text(item.end.formatted(date: .omitted, time: .shortened))
                                                .font(.system(size: 8))
                                                .foregroundStyle(.white.opacity(0.85))
                                        }
                                    }
                                }
                                .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                            }
                            .offset(y: offset)
                            .onTapGesture {
                                onTapItem(item)
                            }
                            .onLongPressGesture {
                                onLongPressItem(item)
                            }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func position(for item: JournalViewModel.TimelineItem, in contentHeight: CGFloat) -> (CGFloat, CGFloat) {
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { return (0, 0) }

        let clampedStart = max(item.start, dayStart)
        let clampedEnd = min(item.end, dayEnd)

        if clampedStart >= clampedEnd {
            return (0, 0)
        }

        let startOffsetSeconds = clampedStart.timeIntervalSince(dayStart)
        let endOffsetSeconds = clampedEnd.timeIntervalSince(dayStart)
        
        let totalSecondsInDay = 24.0 * 3600.0

        let offset = CGFloat(startOffsetSeconds / totalSecondsInDay) * contentHeight
        let durationSeconds = endOffsetSeconds - startOffsetSeconds
        let height = CGFloat(durationSeconds / totalSecondsInDay) * contentHeight
        
        guard height > 0 else { return (0, 0) }
        
        return (offset, height)
    }
}
