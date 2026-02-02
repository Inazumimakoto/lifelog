//
//  JournalView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI
import UIKit
import MapKit

enum CalendarMode: Equatable {
    case schedule
    case review
}

private enum ReviewContentMode: String, CaseIterable, Identifiable {
    case diary = "日記"
    case map = "地図"

    var id: String { rawValue }
}

private enum ReviewMapPeriod: String, CaseIterable, Identifiable {
    case month = "今月"
    case all = "すべて"

    var id: String { rawValue }
}

private enum MultiDayPosition {
    case none      // Single-day or non-multi-day
    case start     // First day of multi-day event
    case middle    // Middle day of multi-day event
    case end       // Last day of multi-day event
}

private struct CalendarPreviewText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.adjustsFontSizeToFitWidth = false
        label.allowsDefaultTighteningForTruncation = true
        label.textColor = .label
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.font = Self.previewFont
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.text = text
        uiView.font = Self.previewFont
    }

    @available(iOS 16.0, *)
    static func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize {
        let targetWidth = proposal.width ?? .greatestFiniteMagnitude
        let targetHeight = proposal.height ?? .greatestFiniteMagnitude
        let size = uiView.sizeThatFits(CGSize(width: targetWidth, height: targetHeight))
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    private static let previewFont: UIFont = {
        let baseFont = UIFont.systemFont(ofSize: 9, weight: .medium)
        let descriptor = baseFont.fontDescriptor
        let traits = (descriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]) ?? [:]
        var condensedTraits = traits
        condensedTraits[.width] = -0.2
        let condensedDescriptor = descriptor.addingAttributes([.traits: condensedTraits])
        return UIFont(descriptor: condensedDescriptor, size: 9)
    }()
}

private struct DayPreviewItem: Identifiable {
    enum Kind {
        case event
        case task
    }
    let id: String
    let title: String
    let color: Color
    let timeText: String?
    let kind: Kind
    
    // Multi-day event info (nil for tasks or when not needed)
    let eventStartDate: Date?
    let eventEndDate: Date?
    
    var isMultiDayEvent: Bool {
        guard kind == .event, let start = eventStartDate, let end = eventEndDate else { return false }
        let calendar = Calendar.current
        let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: end) ?? end
        return !calendar.isDate(start, inSameDayAs: adjustedEnd)
    }
    
    func multiDayPosition(on date: Date) -> MultiDayPosition {
        guard isMultiDayEvent, let start = eventStartDate, let end = eventEndDate else {
            return .none
        }
        let calendar = Calendar.current
        let isStart = calendar.isDate(date, inSameDayAs: start)
        let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: end) ?? end
        let isEnd = calendar.isDate(date, inSameDayAs: adjustedEnd)
        
        if isStart { return .start }
        if isEnd { return .end }
        return .middle
    }
}


struct JournalView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let store: AppDataStore
    @StateObject private var viewModel: JournalViewModel
    private let monthPagerHeight: CGFloat = 700
    private let monthPagerRadius = 3
    @State private var monthPagerAnchors: [Date] = []
    @State private var monthPagerSelection: Int = 0
    @State private var isSyncingMonthPager = false
    private let weekPagerHeight: CGFloat = 780
    private let weekPagerRadius = 8
    @State private var weekPagerAnchors: [Date] = []
    @State private var weekPagerSelection: Int = 0
    @State private var isSyncingWeekPager = false
    @State private var showTaskEditor = false
    @State private var showEventEditor = false
    @State private var showDiaryEditor = false
    @State private var editingEvent: CalendarEvent?
    @State private var editingTask: Task?
    @State private var tappedTimelineItem: JournalViewModel.TimelineItem?
    @State private var timelineEventToDelete: CalendarEvent?
    @State private var showTimelineDeleteConfirmation = false
    @State private var showAddMenu = false
    @State private var pendingAddDate: Date?
    @State private var newItemDate: Date?
    @State private var diaryEditorDate: Date?
    @State private var isDiaryOpeningFromReview = false
    @State private var isProgrammaticWeekPagerChange = false
    private let detailPagerRadius = 7
    @State private var detailPagerAnchors: [Date] = []
    @State private var detailPagerSelection: Int = 0
    @State private var isSyncingDetailPager = false
    @Namespace private var selectionNamespace
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showingDetailPanel = false
    @State private var pendingDiaryDate: Date?
    @State private var calendarSyncTrigger = 0
    @State private var showCalendarSettings = false // Used internally by SettingsView logic if needed, but we are moving entry point
    @State private var showSettings = false
    @State private var showTaskManager = false
    @State private var showEventManager = false
    @State private var showMemoEditor = false
    @AppStorage("showMoodOnReviewCalendar") private var showMoodOnReviewCalendar = true
    @State private var calendarMode: CalendarMode = .schedule
    @State private var reviewContentMode: ReviewContentMode = .diary
    @State private var reviewMapPeriod: ReviewMapPeriod = .month
    @State private var selectedReviewDate: Date? = Date().startOfDay
    @State private var reviewPhotoIndex: Int = 0
    @State private var didInitReviewPhotoIndex: Bool = false
    @State private var isShowingReviewPhotoViewer = false
    @State private var reviewPhotoViewerDate: Date?
    @State private var reviewPhotoViewerIndex: Int = 0
    @State private var pendingPhotoViewerDate: Date?
    @State private var didInitialSetup = false
    @State private var deferredCalendarSyncTask: _Concurrency.Task<Void, Never>?
    @State private var deferredPreloadTask: _Concurrency.Task<Void, Never>?
    
    private let resetTrigger: Int

    init(store: AppDataStore, resetTrigger: Int = 0) {
        self.store = store
        self.resetTrigger = resetTrigger
        _viewModel = StateObject(wrappedValue: JournalViewModel(store: store))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                mainScrollContent(proxy: proxy)
            }
            
            // FAB
            FloatingButton(iconName: "plus") {
                Button {
                    newItemDate = viewModel.selectedDate
                    showTaskEditor = true
                } label: {
                    Label("タスクを追加", systemImage: "checkmark.circle")
                }
                Button {
                    newItemDate = viewModel.selectedDate
                    showEventEditor = true
                } label: {
                    Label("予定を追加", systemImage: "calendar")
                }
            }
        }
        .fullScreenCover(item: $reviewPhotoViewerDate) { date in
            DiaryPhotoViewerView(viewModel: makeDiaryViewModel(for: date),
                                 initialIndex: reviewPhotoViewerIndex)
        }
        .toolbar {
            journalToolbar
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
        .sheet(item: $diaryEditorDate) { date in
            NavigationStack {
                DiaryEditorView(store: store, date: date)
            }
        }
        .sheet(item: $editingEvent) { event in
            NavigationStack {
                CalendarEventEditorView(event: event,
                                        onSave: { updated in store.updateCalendarEvent(updated) },
                                        onDelete: { store.deleteCalendarEvent(event.id) })
            }
        }
        .sheet(item: $editingTask) { task in
            NavigationStack {
                TaskEditorView(task: task,
                               defaultDate: task.startDate ?? task.endDate ?? viewModel.selectedDate,
                               onSave: { updated in store.updateTask(updated) },
                               onDelete: { store.deleteTasks(withIDs: [task.id]) })
            }
        }
        .fullScreenCover(isPresented: $showMemoEditor) {
            NavigationStack {
                MemoEditorView(store: store)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(isPresented: $showTaskManager) {
            NavigationStack {
                TasksView(store: store)
            }
        }
        .sheet(isPresented: $showEventManager) {
            NavigationStack {
                EventsView(store: store)
            }
        }
        .confirmationDialog("予定を削除", isPresented: $showTimelineDeleteConfirmation, presenting: timelineEventToDelete) { event in
            Button("削除", role: .destructive) {
                store.deleteCalendarEvent(event.id)
                timelineEventToDelete = nil
            }
            Button("キャンセル", role: .cancel) {
                timelineEventToDelete = nil
            }
        } message: { event in
            Text("\"\(event.title)\" を削除しますか？")
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
            if didInitialSetup == false {
                didInitialSetup = true
                prepareMonthPagerIfNeeded()
                prepareWeekPagerIfNeeded()
                prepareDetailPagerIfNeeded()
            }
            scheduleDeferredPreload()
            scheduleDeferredCalendarSync()
        }
        .onDisappear {
            deferredCalendarSyncTask?.cancel()
            deferredCalendarSyncTask = nil
            deferredPreloadTask?.cancel()
            deferredPreloadTask = nil
        }
        .task(id: calendarSyncTrigger) {
            await viewModel.syncExternalCalendarsIfNeeded()
        }
        .onChange(of: scenePhase, initial: false) { oldPhase, newPhase in
            if oldPhase != .active && newPhase == .active {
                scheduleDeferredCalendarSync()
            }
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
            if isSyncingDetailPager {
                isSyncingDetailPager = false
            }
            ensureDetailPagerIncludes(date: newDate)
        }
        .onChange(of: viewModel.monthAnchor) { _, newAnchor in
            guard viewModel.displayMode == .month else { return }
            ensureMonthPagerIncludes(date: newAnchor)
            _Concurrency.Task {
                await viewModel.syncExternalCalendarsIfNeeded(anchorDate: newAnchor)
            }
        }
        .onChange(of: calendarMode) { _, newMode in
            if newMode == .review {
                viewModel.displayMode = .month
                selectedReviewDate = viewModel.selectedDate
                reviewPhotoIndex = preferredPhotoIndex(for: store.entry(for: selectedReviewDate ?? viewModel.selectedDate))
                reviewContentMode = .diary
            }
        }
        .onChange(of: resetTrigger) { _, _ in
            // 他のタブから戻った時に「予定カレンダー」「月表示」にリセット
            if calendarMode != .schedule {
                calendarMode = .schedule
            }
            if viewModel.displayMode != .month {
                viewModel.displayMode = .month
            }
        }
        .onChange(of: viewModel.monthAnchor) { _, newAnchor in
            guard calendarMode == .review else { return }
            if let selected = selectedReviewDate,
               Calendar.current.isDate(selected, equalTo: newAnchor, toGranularity: .month) == false {
                selectedReviewDate = newAnchor
                reviewPhotoIndex = preferredPhotoIndex(for: store.entry(for: newAnchor))
            } else if selectedReviewDate == nil {
                selectedReviewDate = newAnchor
                reviewPhotoIndex = preferredPhotoIndex(for: store.entry(for: newAnchor))
            }
        }
        .onChange(of: selectedReviewDate) { _, newDate in
            reviewPhotoIndex = preferredPhotoIndex(for: store.entry(for: newDate ?? viewModel.monthAnchor))
        }
    }

    @ViewBuilder
    private func mainScrollContent(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                titleRow
                monthHeader
                if calendarMode == .schedule {
                    modePicker
                } else {
                    reviewModePicker
                }
                if activeDisplayMode == .month {
                    weekdayHeader
                        .padding(.horizontal, 4)
                } else if activeDisplayMode == .week {
                    weekdayHeader
                        .padding(.horizontal, 4)
                }
                calendarSwitcher
                if calendarMode == .schedule {
                    contentArea
                    calendarLegend
                } else {
                    if reviewContentMode == .diary {
                        reviewDetail
                    } else {
                        reviewMap
                    }
                }
                if viewModel.calendarAccessDenied {
                    Text("設定 > プライバシーとセキュリティ > カレンダーでlifelogへのアクセスを許可すると外部カレンダーの予定が表示されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .onAppear { scrollProxy = proxy }
        .popover(item: $tappedTimelineItem) { item in
            let deleteAction: (() -> Void)? = {
                guard item.kind == .event,
                      let id = item.sourceId,
                      let event = store.calendarEvents.first(where: { $0.id == id }) else { return nil }
                return {
                    tappedTimelineItem = nil
                    timelineEventToDelete = event
                    showTimelineDeleteConfirmation = true
                }
            }()

            TimelineItemDetailView(
                item: item,
                onEdit: {
                    tappedTimelineItem = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        handleEdit(for: item)
                    }
                },
                onDelete: deleteAction
            )
        }
        .sheet(isPresented: $showingDetailPanel) {
            NavigationStack {
                let snapshot = calendarSnapshot(for: viewModel.selectedDate)
                let pager = detailPager(includeAddButtons: true, showHeader: true, minHeight: 640)
                VStack(spacing: 0) {
                    pager
                        .padding(.horizontal, 16)
                    Spacer(minLength: 0)
                    
                    // Apple Weather Attribution (Required by WeatherKit) - フッター
                    if snapshot.healthSummary?.weatherCondition != nil {
                        Link(destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 9))
                                Text("Weather")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.secondary.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") {
                            showingDetailPanel = false
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .onAppear {
                prepareDetailPagerIfNeeded()
                ensureDetailPagerIncludes(date: viewModel.selectedDate)
            }
            .onDisappear {
                // シートが完全に閉じた後に次の画面を表示
                if let pending = pendingPhotoViewerDate {
                    pendingPhotoViewerDate = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        reviewPhotoViewerDate = pending
                    }
                } else if let pending = pendingDiaryDate {
                    pendingDiaryDate = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        diaryEditorDate = pending
                    }
                }
            }
            .onChange(of: showingDetailPanel) { _, isShowing in
                guard isShowing == false else { return }
                if isDiaryOpeningFromReview == false {
                    pendingDiaryDate = nil
                }
                isDiaryOpeningFromReview = false
            }
            .presentationDetents(
                calendarMode == .schedule
                ? [.large]
                : [.fraction(0.66)]
            )
            .presentationDragIndicator(.visible)
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
        let isShowingTodayMonth = calendar.isDate(viewModel.monthAnchor, equalTo: today, toGranularity: .month)
        if calendarMode == .schedule {
            let isOnToday = calendar.isDate(viewModel.selectedDate, inSameDayAs: today)
            if activeDisplayMode == .week {
                guard weekPagerAnchors.indices.contains(weekPagerSelection) else { return true }
                let currentWeekAnchor = weekPagerAnchors[weekPagerSelection]
                let isOnTodayWeek = calendar.isDate(currentWeekAnchor, equalTo: today, toGranularity: .weekOfYear)
                return !(isShowingTodayMonth && isOnToday && isOnTodayWeek)
            }
            return !(isShowingTodayMonth && isOnToday)
        } else {
            let selected = selectedReviewDate ?? viewModel.monthAnchor
            let isOnToday = calendar.isDate(selected, inSameDayAs: today)
            return !(isShowingTodayMonth && isOnToday)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("カレンダー")
                .font(.largeTitle.bold())
            Spacer()
            Picker("", selection: $calendarMode) {
                Text("予定").tag(CalendarMode.schedule)
                Text("振り返り").tag(CalendarMode.review)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.4)) {
                    viewModel.stepBackward(displayMode: activeDisplayMode)
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
                    if calendarMode == .schedule {
                        let longDuration = 0.55
                        let shortDuration = 0.25
                        let needsLongAnimation: Bool
                        switch activeDisplayMode {
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
                    } else {
                        // 振り返りカレンダーでも距離に応じたアニメーション
                        let longDuration = 0.55
                        let shortDuration = 0.25
                        let needsLongAnimation = calendar.isDate(viewModel.monthAnchor, equalTo: today, toGranularity: .month) == false
                        let duration = needsLongAnimation ? longDuration : shortDuration
                        withAnimation(.easeInOut(duration: duration)) {
                            viewModel.setMonthAnchor(today)
                            ensureMonthPagerIncludes(date: today)
                            selectedReviewDate = today
                        }
                    }
                }
                .font(.caption)
            }
            Button(action: {
                withAnimation(.easeInOut(duration: 0.4)) {
                    viewModel.stepForward(displayMode: activeDisplayMode)
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

    private var reviewModePicker: some View {
        Picker("表示切替", selection: $reviewContentMode) {
            ForEach(ReviewContentMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var headerTitle: String {
        if activeDisplayMode == .month {
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
            if activeDisplayMode == .month {
                monthPager
            } else if activeDisplayMode == .week {
                weekPager
            }
        }
    }

    private var monthPager: some View {
        TabView(selection: $monthPagerSelection) {
            ForEach(Array(monthPagerAnchors.enumerated()), id: \.offset) { index, anchor in
                VStack(spacing: 0) {
                    if calendarMode == .review {
                        reviewMonthCalendar(for: anchor)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                            .padding(.horizontal, 4)
                    } else {
                        monthCalendar(for: anchor)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                            .padding(.horizontal, 4)
                        Spacer(minLength: 0)
                    }
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
            
            // 振り返りモードの場合、前後月含めてプリフェッチ
            if calendarMode == .review {
                prefetchPhotosForMonths(around: anchor)
            }
        }
    }

    private var monthGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private func monthCalendar(for anchor: Date) -> some View {
        let columns = monthGridColumns
        let itemLimit = 4
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(viewModel.calendarDays(for: anchor)) { day in
                monthDayCell(day, itemLimit: itemLimit)
            }
        }
        .animation(.easeInOut, value: viewModel.selectedDate)
    }

    @ViewBuilder
    private func monthDayCell(_ day: JournalViewModel.CalendarDay, itemLimit: Int) -> some View {
        let previews = dayPreviewItems(events: day.events, tasks: day.tasks, on: day.date)
        let (visible, overflow) = previewDisplay(previews, limit: itemLimit)
        VStack(alignment: .leading, spacing: 2) {
            // Date fixed in top-left
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(day.isWithinDisplayedMonth ? .primary : .secondary)
                .padding(.horizontal, 4)  // Date gets its own padding
            
            // Items below the date
            ForEach(visible) { item in
                if item.kind == .event {
                    eventBarView(item: item, date: day.date)
                } else {
                    CalendarPreviewText(text: previewLabel(for: item))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(item.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        .clipped()
                }
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)  // Overflow text gets padding
            }
            
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        // Remove .padding(.horizontal, 4) from VStack
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 88)
        // Use a mask that allows horizontal overflow (for connected bars)
        // but clips vertical overflow (to keep fixed height).
        // Padding -20 extends the mask horizontally by 20pt on each side.
        .mask(Rectangle().padding(.horizontal, -20))
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
                                           isSource: viewModel.displayMode == .month && day.isWithinDisplayedMonth)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openDayDetail(for: day.date)
        }
    }

    /// 凡例：各カテゴリの色を表示。タップでカレンダー設定を開く
    private var calendarLegend: some View {
        let links = store.appState.calendarCategoryLinks
            .filter { $0.categoryId != nil }
        let uniqueCategories = Set(links.compactMap { $0.categoryId })
        
        return Button {
            showCalendarSettings = true
        } label: {
            HStack(spacing: 12) {
                ForEach(Array(uniqueCategories).sorted(), id: \.self) { category in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(CategoryPalette.color(for: category))
                            .frame(width: 8, height: 8)
                        Text(category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    private var contentArea: some View {
        VStack(spacing: 12) {
            if activeDisplayMode == .week {
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
                        .padding(.top, 17)
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
        let itemLimit = 4
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(dates, id: \.self) { date in
                weekDayCell(date, itemLimit: itemLimit)
            }
        }
        .animation(.easeInOut, value: viewModel.selectedDate)
    }

    @ViewBuilder
    private func weekDayCell(_ date: Date, itemLimit: Int) -> some View {
        let previews = dayPreviewItems(for: date)
        let (visible, overflow) = previewDisplay(previews, limit: itemLimit)
        VStack(alignment: .leading, spacing: 2) {
            // Date fixed in top-left
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)  // Date gets its own padding
            
            // Items below the date
            ForEach(visible) { item in
                if item.kind == .event {
                    eventBarView(item: item, date: date)
                } else {
                    CalendarPreviewText(text: previewLabel(for: item))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(item.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        .clipped()
                }
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)  // Overflow text gets padding
            }
            
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        // Remove .padding(.horizontal, 4) from VStack
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 88)
        // Mask allowing horizontal overflow to connect bars
        .mask(Rectangle().padding(.horizontal, -20))
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
            openDayDetail(for: date)
        }
    }

    private var activeDisplayMode: JournalViewModel.DisplayMode {
        calendarMode == .review ? .month : viewModel.displayMode
    }

    private func reviewMonthCalendar(for anchor: Date) -> some View {
        let columns = monthGridColumns
        let days = viewModel.calendarDays(for: anchor)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(days) { day in
                let isSelected = selectedReviewDate?.isSameDay(as: day.date) ?? false
                ReviewDayCell(
                    day: day,
                    isSelected: isSelected,
                    showMoodOnReviewCalendar: showMoodOnReviewCalendar,
                    onTap: { openDayDetail(for: day.date) }
                )
            }
        }
        .animation(.easeInOut, value: selectedReviewDate)
        .onAppear {
            // プリフェッチ: 今月 + 前後の月の写真を裏で読み込み
            prefetchPhotosForMonths(around: anchor)
        }
    }
    
    // 前後の月も含めてプリフェッチ
    private func prefetchPhotosForMonths(around anchor: Date) {
        let calendar = Calendar.current
        var allPaths: [String] = []
        
        // 前月・今月・次月の3ヶ月分
        for offset in -1...1 {
            if let monthDate = calendar.date(byAdding: .month, value: offset, to: anchor) {
                let days = viewModel.calendarDays(for: monthDate)
                let paths = days.compactMap { $0.diary?.favoritePhotoPath }
                allPaths.append(contentsOf: paths)
            }
        }
        
        if !allPaths.isEmpty {
            PhotoStorage.prefetchThumbnails(paths: allPaths)
        }
    }

    private var reviewDetail: some View {
        VStack(spacing: 12) {
            let targetDate = selectedReviewDate ?? viewModel.monthAnchor
            reviewDetailCard(for: targetDate)
        }
    }

    private var reviewMap: some View {
        ReviewMapView(entries: reviewMapEntries(for: reviewMapPeriod),
                      period: $reviewMapPeriod,
                      onOpenDiary: { openDiaryEditor(for: $0) })
    }

    private func preferredPhotoIndex(for diary: DiaryEntry?) -> Int {
        guard let diary else { return 0 }
        if let favorite = diary.favoritePhotoPath,
           let index = diary.photoPaths.firstIndex(of: favorite) {
            return index
        }
        return 0
    }

    private func reviewMapEntries(for period: ReviewMapPeriod) -> [ReviewLocationEntry] {
        let calendar = Calendar.current
        let anchor = selectedReviewDate ?? viewModel.monthAnchor
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        func isIncluded(_ date: Date) -> Bool {
            switch period {
            case .all:
                return true
            case .month:
                return date >= monthStart && date < monthEnd
            }
        }

        var results: [ReviewLocationEntry] = []
        for entry in store.diaryEntries {
            let entryDate = entry.date.startOfDay
            guard isIncluded(entryDate) else { continue }
            let locations: [DiaryLocation]
            if entry.locations.isEmpty,
               let name = entry.locationName,
               name.isEmpty == false,
               let latitude = entry.latitude,
               let longitude = entry.longitude {
                locations = [
                    DiaryLocation(name: name,
                                  address: nil,
                                  latitude: latitude,
                                  longitude: longitude,
                                  mapItemURL: nil)
                ]
            } else {
                locations = entry.locations
            }
            for location in locations {
                results.append(ReviewLocationEntry(date: entryDate, location: location))
            }
        }
        return results.sorted { $0.date > $1.date }
    }

    private func conditionEmoji(for score: Int) -> String {
        switch score {
        case 1: return "😫"
        case 2: return "😟"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😄"
        default: return "❓"
        }
    }

    private func reviewDetailCard(for date: Date) -> some View {
        let diary = store.entry(for: date)
        let photoPaths = diary?.photoPaths ?? []
        let preferredIndex = preferredPhotoIndex(for: diary)
        let photoSelection = Binding(
            get: { reviewPhotoIndex },
            set: { newValue in
                reviewPhotoIndex = newValue
            }
        )
        return ReviewDetailPanel(
            date: date,
            store: store,
            diary: diary,
            photoPaths: photoPaths,
            preferredIndex: preferredIndex,
            photoSelection: photoSelection,
            reviewPhotoViewerIndex: $reviewPhotoViewerIndex,
            pendingPhotoViewerDate: $pendingPhotoViewerDate,
            showingDetailPanel: $showingDetailPanel,
            didInitReviewPhotoIndex: $didInitReviewPhotoIndex,
            reviewPhotoIndex: $reviewPhotoIndex,
            onOpenDiary: { openDiaryEditor(for: $0) }
        )
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
            .frame(height: timelineHeight + 96)
        }
    }

    private func toggleTask(_ task: Task) {
        // ハプティックフィードバック
        if task.isCompleted {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            store.toggleTaskCompletion(task.id)
        }
    }

    private func toggleHabit(_ habit: Habit, on date: Date) {
        store.toggleHabit(habit.id, on: date)
    }

    private func openDiaryEditor(for date: Date) {
        let targetDate = date.startOfDay
        viewModel.selectedDate = targetDate
        let fromReview = calendarMode == .review
        isDiaryOpeningFromReview = fromReview
        if showingDetailPanel || fromReview {
            pendingDiaryDate = targetDate
            showingDetailPanel = false
        } else {
            pendingDiaryDate = nil
            diaryEditorDate = targetDate
        }
    }

    private func handleQuickAction(on date: Date) {
        viewModel.selectedDate = date
        pendingAddDate = date
        showAddMenu = true
    }

    private func openDayDetail(for date: Date) {
        let target = date.startOfDay
        viewModel.selectedDate = target
        selectedReviewDate = target
        ensureDetailPagerIncludes(date: target)
        showingDetailPanel = true
    }

    private func weekDates(for anchor: Date) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)) ?? anchor
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func calendarSnapshot(for date: Date) -> CalendarDetailSnapshot {
        let events = store.events(on: date)
        // 詳細シートでは開始〜終了日の範囲内のタスクを表示
        let sortedTasks = viewModel.tasksInRange(on: date).sorted(by: calendarTaskSort)
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

    private func detailPager(includeAddButtons: Bool, showHeader: Bool = false, minHeight: CGFloat = 520) -> some View {
        TabView(selection: $detailPagerSelection) {
            ForEach(Array(detailPagerAnchors.enumerated()), id: \.offset) { index, anchor in
                let snapshot = calendarSnapshot(for: anchor)
                let content: AnyView = calendarMode == .schedule
                ? AnyView(
                    CalendarDetailPanel(snapshot: snapshot,
                                        store: store,
                                        includeAddButtons: includeAddButtons,
                                        showHeader: showHeader,
                                        onToggleTask: { toggleTask($0) },
                                        onToggleHabit: { toggleHabit($0, on: snapshot.date) },
                                        onOpenDiary: { openDiaryEditor(for: $0) })
                )
                : AnyView(reviewDetailCard(for: anchor))
                content.tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
        .frame(minHeight: calendarMode == .schedule ? minHeight : nil)
        .onChange(of: detailPagerSelection) { _, newSelection in
            guard detailPagerAnchors.indices.contains(newSelection) else { return }
            let date = detailPagerAnchors[newSelection]
            if date.startOfDay != viewModel.selectedDate.startOfDay {
                isSyncingDetailPager = true
                viewModel.selectedDate = date
            }
            extendDetailPagerIfNeeded(at: newSelection)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.isSyncingDetailPager = false
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

    private func makeDiaryViewModel(for date: Date) -> DiaryViewModel {
        DiaryViewModel(store: store, date: date)
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

    private func dayPreviewItems(for date: Date) -> [DayPreviewItem] {
        dayPreviewItems(events: store.events(on: date),
                        tasks: viewModel.tasks(on: date),
                        on: date)
    }

    private func dayPreviewItems(events: [CalendarEvent], tasks: [Task], on date: Date) -> [DayPreviewItem] {
        let sortedEvents = events.sorted { lhs, rhs in
            // Multi-day events first
            let lhsMulti = isMultiDayEvent(lhs)
            let rhsMulti = isMultiDayEvent(rhs)
            if lhsMulti != rhsMulti {
                return lhsMulti && !rhsMulti
            }
            // Then all-day events
            if lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay && rhs.isAllDay == false
            }
            return lhs.startDate < rhs.startDate
        }
        let sortedTasks = tasks.sorted(by: calendarTaskSort)

        let eventItems: [DayPreviewItem] = sortedEvents.map {
            DayPreviewItem(id: $0.id.uuidString,
                           title: $0.title,
                           color: CategoryPalette.color(for: $0.calendarName),
                           timeText: previewTimeLabel(for: $0),
                           kind: .event,
                           eventStartDate: $0.startDate,
                           eventEndDate: $0.endDate)
        }
        let taskItems: [DayPreviewItem] = sortedTasks.map {
            DayPreviewItem(id: $0.id.uuidString,
                           title: $0.title,
                           color: $0.priority.color,
                           timeText: taskTimeLabel(for: $0, on: date),
                           kind: .task,
                           eventStartDate: nil,
                           eventEndDate: nil)
        }
        return eventItems + taskItems
    }
    
    private func isMultiDayEvent(_ event: CalendarEvent) -> Bool {
        let calendar = Calendar.current
        let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
        return !calendar.isDate(event.startDate, inSameDayAs: adjustedEnd)
    }


    private func previewDisplay(_ items: [DayPreviewItem], limit: Int) -> ([DayPreviewItem], Int) {
        guard items.count > limit else { return (items, 0) }
        let visibleCount = max(1, limit - 1)
        let visible = Array(items.prefix(visibleCount))
        let overflow = items.count - visibleCount
        return (visible, overflow)
    }

    private func previewLabel(for item: DayPreviewItem) -> String {
        item.title
    }
    
    @ViewBuilder
    private func eventBarView(item: DayPreviewItem, date: Date) -> some View {
        let position = item.multiDayPosition(on: date)
        let showTitle = position == .start || position == .none
        let isMultiDay = item.isMultiDayEvent
        
        // Determine corner radii based on position
        let leftRadius: CGFloat = (position == .start || position == .none) ? 4 : 0
        let rightRadius: CGFloat = (position == .end || position == .none) ? 4 : 0
        
        // Horizontal extension to bridge grid spacing
        // Adjusted to -2 (exact match for 4px gap) to avoid any overlap
        let leadingPadding: CGFloat = (position == .start || position == .none) ? 0 : -2
        let trailingPadding: CGFloat = (position == .end || position == .none) ? 0 : -2
        
        HStack(spacing: 0) {
            if showTitle {
                CalendarPreviewText(text: item.title)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Empty spacer to maintain height for middle/end segments
                Text(" ")
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .padding(.horizontal, showTitle ? 3 : 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: leftRadius,
                bottomLeadingRadius: leftRadius,
                bottomTrailingRadius: rightRadius,
                topTrailingRadius: rightRadius
            )
            .fill(item.color.opacity(0.2))
        )
        .clipped()
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
    }


    private func previewTimeLabel(for event: CalendarEvent) -> String? { nil }

    private func taskTimeLabel(for task: Task, on date: Date) -> String? { nil }

    private func hasDiaryEntry(on date: Date) -> Bool {
        if let entry = store.entry(for: date) {
            return entry.text.isEmpty == false || entry.photoPaths.isEmpty == false || entry.mood != nil || entry.conditionScore != nil
        }
        return false
    }

    private func setWeekPagerSelection(_ index: Int) {
        isProgrammaticWeekPagerChange = true
        weekPagerSelection = index
    }

    private func refreshExternalCalendars() {
        _Concurrency.Task {
            await viewModel.syncExternalCalendarsIfNeeded(force: true, anchorDate: viewModel.monthAnchor)
        }
    }

    private func scheduleDeferredCalendarSync() {
        deferredCalendarSyncTask?.cancel()
        deferredCalendarSyncTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 350_000_000)
            calendarSyncTrigger += 1
        }
    }

    private func scheduleDeferredPreload() {
        deferredPreloadTask?.cancel()
        deferredPreloadTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            viewModel.preloadMonths(around: viewModel.monthAnchor, radius: 1)
        }
    }

    @ToolbarContentBuilder
    private var journalToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showMemoEditor = true
            } label: {
                Image(systemName: "note.text")
            }

            Button(action: refreshExternalCalendars) {
                Image(systemName: "arrow.clockwise")
            }

            Menu {
                Button {
                    showEventManager = true
                } label: {
                    Label("予定リスト", systemImage: "calendar")
                }
                Button {
                    showTaskManager = true
                } label: {
                    Label("タスクリスト", systemImage: "checklist")
                }
            } label: {
                Image(systemName: "list.bullet")
            }

            // 振り返りモード時のみ気分表示トグルを表示
            if calendarMode == .review {
                Button {
                    showMoodOnReviewCalendar.toggle()
                } label: {
                    Image(systemName: showMoodOnReviewCalendar ? "face.smiling" : "face.dashed")
                        .foregroundStyle(.primary)
                }
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct TimelineItemDetailView: View {
    let item: JournalViewModel.TimelineItem
    var onEdit: () -> Void
    var onDelete: (() -> Void)? = nil

    private var canDeleteEvent: Bool {
        item.kind == .event && onDelete != nil
    }
    
    private var timeLabel: String {
        if item.isAllDay {
            return "終日"
        }
        return "\(item.start.formatted(date: .omitted, time: .shortened)) - \(item.end.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.title2.bold())
                
                Text(timeLabel)
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
    let store: AppDataStore
    var includeAddButtons: Bool
    var showHeader: Bool = false
    var onToggleTask: (Task) -> Void
    var onToggleHabit: (Habit) -> Void
    var onOpenDiary: (Date) -> Void
    
    // シート管理用State
    @State private var editingTask: Task?
    @State private var editingEvent: CalendarEvent?
    @State private var showAddTask = false
    @State private var showAddEvent = false
    @State private var diaryEditorDate: Date?

    private var hasDiaryEntry: Bool {
        if let entry = snapshot.diaryEntry {
            return entry.text.isEmpty == false
        }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // ヘッダー（シート用）
                if showHeader {
                    dateHeader
                }

                summaryRow
                OverviewSection(icon: "calendar",
                                title: "予定",
                                actionTitle: includeAddButtons ? "予定を追加" : nil,
                                action: includeAddButtons ? { showAddEvent = true } : nil) {
                    if snapshot.events.isEmpty {
                        placeholder("予定はありません")
                    } else {
                        VStack(spacing: 12) {
                            ForEach(snapshot.events) { event in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(color(for: event.calendarName))
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 6)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(event.title)
                                                .font(.body.weight(.semibold))
                                            // リマインダー設定済みインジケーター（イベント個別またはカテゴリ設定）
                                            if hasReminder(for: event) {
                                                Image(systemName: "bell.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Label(eventTimeLabel(for: event), systemImage: "clock")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 6) {
                                            Text(event.calendarName)
                                                .font(.caption2)
                                                .foregroundStyle(color(for: event.calendarName))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(color(for: event.calendarName).opacity(0.15), in: Capsule())
                                            // 外部カレンダーの場合はインジケーター表示
                                            if event.sourceCalendarIdentifier != nil {
                                                Label("外部", systemImage: "arrow.down.circle")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                    // 外部カレンダーでない場合のみ編集ボタン表示
                                    if event.sourceCalendarIdentifier == nil {
                                        Button {
                                            editingEvent = event
                                        } label: {
                                            Image(systemName: "square.and.pencil")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
                OverviewSection(icon: "checkmark.circle",
                                title: "タスク",
                                actionTitle: includeAddButtons ? "タスクを追加" : nil,
                                action: includeAddButtons ? { showAddTask = true } : nil) {
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
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: snapshot.pendingTasks.map(\.id))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: snapshot.completedTasks.map(\.id))
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
                                        AnimatedCheckmark(
                                            isCompleted: status.isCompleted,
                                            color: Color(hex: status.habit.colorHex) ?? Color.accentColor,
                                            size: 26
                                        )
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
                                if let locationLabel = locationLabel(for: entry) {
                                    Label(locationLabel, systemImage: "mappin.and.ellipse")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
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
            }
        }
        .sheet(item: $editingTask) { task in
            NavigationStack {
                TaskEditorView(task: task,
                               defaultDate: task.startDate ?? task.endDate ?? snapshot.date,
                               onSave: { updated in store.updateTask(updated) },
                               onDelete: { store.deleteTasks(withIDs: [task.id]) })
            }
        }
        .sheet(item: $editingEvent) { event in
            NavigationStack {
                CalendarEventEditorView(event: event,
                                        onSave: { updated in store.updateCalendarEvent(updated) },
                                        onDelete: { store.deleteCalendarEvent(event.id) })
            }
        }
        .sheet(isPresented: $showAddTask) {
            NavigationStack {
                TaskEditorView(defaultDate: snapshot.date) { task in
                    store.addTask(task)
                }
            }
        }
        .sheet(isPresented: $showAddEvent) {
            NavigationStack {
                CalendarEventEditorView(defaultDate: snapshot.date) { event in
                    store.addCalendarEvent(event)
                }
            }
        }
        .sheet(item: $diaryEditorDate) { editorDate in
            NavigationStack {
                DiaryEditorView(store: store, date: editorDate)
                    .id(editorDate)
            }
        }
    }



    private var dateHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.date.yearString)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(snapshot.date.monthDayWeekdayString)
                    .font(.largeTitle.bold())
            }
            
            Spacer()
            
            // 天気（右側）
            if let summary = snapshot.healthSummary,
               let condition = summary.weatherCondition {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(condition)
                        .font(.headline)
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        if let high = summary.highTemperature, let low = summary.lowTemperature {
                            Text(String(format: "%.0f°C", (high + low) / 2))
                                .font(.largeTitle.bold())
                            Text(String(format: "%.0f/%.0f", high, low))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
                HStack {
                    TaskRowView(task: task, onToggle: { onToggleTask(task) })
                    Spacer()
                    Button {
                        editingTask = task
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
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
    
    private func hasReminder(for event: CalendarEvent) -> Bool {
        // 個別イベントのリマインダー設定
        if event.reminderMinutes != nil || event.reminderDate != nil {
            return true
        }
        // カテゴリの通知設定（親トグルがオンの場合のみ）
        if NotificationSettingsManager.shared.isEventCategoryNotificationEnabled,
           let setting = NotificationSettingsManager.shared.getSetting(for: event.calendarName),
           setting.enabled {
            return true
        }
        return false
    }

    private func eventTimeLabel(for event: CalendarEvent) -> String {
        if event.isAllDay {
            let calendar = Calendar.current
            let endDay = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
            if calendar.isDate(event.startDate, inSameDayAs: endDay) {
                return "終日"
            }
            return "終日 \(event.startDate.jaMonthDayString) - \(endDay.jaMonthDayString)"
        }
        return "\(event.startDate.formattedTime()) - \(event.endDate.formattedTime())"
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

    private func locationLabel(for entry: DiaryEntry) -> String? {
        if let first = entry.locations.first {
            if entry.locations.count > 1 {
                return "\(first.name) ほか\(entry.locations.count - 1)件"
            }
            return first.name
        }
        if let name = entry.locationName, name.isEmpty == false {
            return name
        }
        return nil
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
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                }
            }
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
                        let itemColor = color(for: item)

                        // Googleカレンダー風: 左に色ストライプ、右は白背景
                        HStack(spacing: 0) {
                            // カラーストライプ（左端）
                            RoundedRectangle(cornerRadius: 3)
                                .fill(itemColor)
                                .frame(width: 4)
                            
                            // コンテンツエリア
                            VStack(alignment: .leading, spacing: 2) {
                                // タイトル
                                Text(item.title)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(blockHeight < threshold ? 1 : 2)
                                
                                // 開始時間
                                if item.isAllDay {
                                    Text("終日")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(item.start.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer(minLength: 0)
                                
                                // 終了時間（2時間以上の予定のみ、終日以外）
                                let duration = item.end.timeIntervalSince(item.start)
                                if !item.isAllDay && duration >= 7200 { // 7200秒 = 2時間
                                    Text(item.end.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(height: blockHeight)
                        .background(itemColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
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
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return (0, 0) }

        let effectiveStart: Date
        let effectiveEnd: Date

        if item.isAllDay {
            effectiveStart = dayStart
            effectiveEnd = calendar.date(byAdding: .minute, value: 90, to: dayStart) ?? dayStart
        } else {
            effectiveStart = item.start
            effectiveEnd = item.end
        }

        let clampedStart = max(effectiveStart, dayStart)
        let clampedEnd = min(effectiveEnd, dayEnd)

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

    private func color(for item: JournalViewModel.TimelineItem) -> Color {
        switch item.kind {
        case .event:
            return CategoryPalette.color(for: item.detail ?? "")
        case .task:
            return .green
        case .sleep:
            return .purple
        }
    }
}

// MARK: - Review Map
private struct ReviewLocationEntry: Identifiable, Hashable {
    let id: String
    let date: Date
    let location: DiaryLocation

    init(date: Date, location: DiaryLocation) {
        self.date = date
        self.location = location
        self.id = "\(date.timeIntervalSince1970)-\(location.id.uuidString)"
    }

    var name: String { location.name }
    var address: String? { location.address }
    var coordinate: CLLocationCoordinate2D { location.coordinate }
}

private struct ReviewMapView: View {
    let entries: [ReviewLocationEntry]
    @Binding var period: ReviewMapPeriod
    let onOpenDiary: (Date) -> Void

    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var selectedEntry: ReviewLocationEntry?
    @State private var hasAppliedRegion = false

    private static let defaultRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.2048, longitude: 138.2529),
                                                          span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12))

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition,
                interactionModes: .all,
                selection: $selectedEntry) {
                ForEach(entries) { entry in
                    Marker(entry.name, coordinate: entry.coordinate)
                        .tag(entry)
                }
            }
            .overlay(alignment: .topTrailing) {
                periodMenu
                    .padding(.top, 8)
                    .padding(.trailing, 12)
            }
            .onChange(of: selectedEntry) { _, newValue in
                guard let entry = newValue else { return }
                onOpenDiary(entry.date)
                selectedEntry = nil
            }
            .onAppear {
                applyRegion(force: true)
            }
            .onChange(of: period) { _, _ in
                applyRegion(force: true)
            }
            .onChange(of: entries) { _, _ in
                applyRegion(force: true)
            }

            if entries.isEmpty {
                emptyState
            } else {
                listSheet
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 420)
    }

    private var periodMenu: some View {
        Menu {
            ForEach(ReviewMapPeriod.allCases) { option in
                Button(option.rawValue) {
                    period = option
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(period.rawValue)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("この期間の場所はありません")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 24)
    }

    private var listSheet: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(entries) { entry in
                        Button {
                            onOpenDiary(entry.date)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(entry.date.jaMonthDayString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 220)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func applyRegion(force: Bool) {
        guard force || hasAppliedRegion == false else { return }
        let region = regionForEntries(entries)
        cameraPosition = .region(region)
        hasAppliedRegion = true
    }

    private func regionForEntries(_ items: [ReviewLocationEntry]) -> MKCoordinateRegion {
        guard let first = items.first else { return Self.defaultRegion }
        var minLat = first.coordinate.latitude
        var maxLat = first.coordinate.latitude
        var minLon = first.coordinate.longitude
        var maxLon = first.coordinate.longitude
        for entry in items.dropFirst() {
            minLat = min(minLat, entry.coordinate.latitude)
            maxLat = max(maxLat, entry.coordinate.latitude)
            minLon = min(minLon, entry.coordinate.longitude)
            maxLon = max(maxLon, entry.coordinate.longitude)
        }
        let latDelta = max(0.05, (maxLat - minLat) * 1.4)
        let lonDelta = max(0.05, (maxLon - minLon) * 1.4)
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: latDelta,
                                                         longitudeDelta: lonDelta))
    }
}

// MARK: - ReviewDetailPanel
private struct ReviewDetailPanel: View {
    let date: Date
    let store: AppDataStore
    let diary: DiaryEntry?
    let photoPaths: [String]
    let preferredIndex: Int
    @Binding var photoSelection: Int
    @Binding var reviewPhotoViewerIndex: Int
    @Binding var pendingPhotoViewerDate: Date?
    @Binding var showingDetailPanel: Bool
    @Binding var didInitReviewPhotoIndex: Bool
    @Binding var reviewPhotoIndex: Int
    let onOpenDiary: (Date) -> Void
    
    @State private var diaryEditorDate: Date?
    @State private var showPhotoViewer = false
    @State private var selectedPhotoIndex = 0
    
    init(date: Date,
         store: AppDataStore,
         diary: DiaryEntry?,
         photoPaths: [String],
         preferredIndex: Int,
         photoSelection: Binding<Int>,
         reviewPhotoViewerIndex: Binding<Int>,
         pendingPhotoViewerDate: Binding<Date?>,
         showingDetailPanel: Binding<Bool>,
         didInitReviewPhotoIndex: Binding<Bool>,
         reviewPhotoIndex: Binding<Int>,
         onOpenDiary: @escaping (Date) -> Void) {
        self.date = date
        self.store = store
        self.diary = diary
        self.photoPaths = photoPaths
        self.preferredIndex = preferredIndex
        self._photoSelection = photoSelection
        self._reviewPhotoViewerIndex = reviewPhotoViewerIndex
        self._pendingPhotoViewerDate = pendingPhotoViewerDate
        self._showingDetailPanel = showingDetailPanel
        self._didInitReviewPhotoIndex = didInitReviewPhotoIndex
        self._reviewPhotoIndex = reviewPhotoIndex
        self.onOpenDiary = onOpenDiary
    }

    private func locationLabel(for entry: DiaryEntry) -> String? {
        if let first = entry.locations.first {
            if entry.locations.count > 1 {
                return "\(first.name) ほか\(entry.locations.count - 1)件"
            }
            return first.name
        }
        if let name = entry.locationName, name.isEmpty == false {
            return name
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let diary, photoPaths.isEmpty == false {
                TabView(selection: $photoSelection) {
                    ForEach(Array(photoPaths.enumerated()), id: \.offset) { index, path in
                        DetailPanelPhotoPage(
                            path: path,
                            index: index,
                            onTap: {
                                selectedPhotoIndex = index
                                showPhotoViewer = true
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 240)
            }
            if let diary {
                if let mood = diary.mood {
                    HStack(spacing: 8) {
                        Text(mood.emoji)
                        Text("気分 \(mood.rawValue)")
                    }
                    .foregroundStyle(.primary)
                }
                if let condition = diary.conditionScore {
                    HStack(spacing: 8) {
                        Text(conditionEmoji(for: condition))
                        Text("体調 \(condition)")
                    }
                    .foregroundStyle(.primary)
                }
                if let place = locationLabel(for: diary) {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .foregroundStyle(.primary)
                }
                if diary.text.isEmpty == false {
                    Text(diary.text)
                        .font(.body)
                        .lineLimit(1)
                }
                Button {
                    onOpenDiary(date)
                } label: {
                    Text("この日の日記を開く")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("この日の日記はまだありません。")
                    .foregroundStyle(.secondary)
                Button {
                    onOpenDiary(date)
                } label: {
                    Text("日記を書く")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // お気に入り写真があればそれを表示
            let maxIndex = max(photoPaths.count - 1, 0)
            let initial = min(preferredIndex, maxIndex)
            photoSelection = max(0, initial)
        }
        .onChange(of: photoPaths) { paths in
            let maxIndex = max(paths.count - 1, 0)
            reviewPhotoIndex = min(reviewPhotoIndex, maxIndex)
        }
        .sheet(item: $diaryEditorDate) { editorDate in
            NavigationStack {
                DiaryEditorView(store: store, date: editorDate)
                    .id(editorDate)
            }
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            DiaryPhotoViewerView(viewModel: DiaryViewModel(store: store, date: date),
                                 initialIndex: selectedPhotoIndex)
        }
    }
    
    private func conditionEmoji(for score: Int) -> String {
        switch score {
        case 1: return "😷"
        case 2: return "😓"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "💪"
        default: return "😐"
        }
    }
}

// MARK: - Review Day Cell (非同期サムネイル対応)
private struct ReviewDayCell: View {
    let day: JournalViewModel.CalendarDay
    let isSelected: Bool
    let showMoodOnReviewCalendar: Bool
    let onTap: () -> Void
    
    @State private var thumbnail: UIImage?
    
    private var hasPhoto: Bool { thumbnail != nil }
    private var moodEmoji: String? { day.diary?.mood?.emoji }
    private var shouldShowMood: Bool { showMoodOnReviewCalendar && moodEmoji != nil }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background: Photo or empty
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            } else {
                Color.clear
            }
            
            // Overlay: Date and mood
            ZStack(alignment: .top) {
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(hasPhoto ? .white : (day.isWithinDisplayedMonth ? .primary : .secondary))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        hasPhoto ? Color.black.opacity(0.4) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                
                if shouldShowMood {
                    Text(moodEmoji!)
                        .font(.caption2)
                        .padding(2)
                        .background(
                            hasPhoto ? Color.black.opacity(0.4) : Color.clear,
                            in: Circle()
                        )
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
            }
            .padding(4)
        }
        .frame(height: 88)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(day.isToday ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .center) {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .opacity(day.isWithinDisplayedMonth ? 1.0 : 0.35)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .task {
            if let path = day.diary?.favoritePhotoPath {
                thumbnail = await PhotoStorage.loadThumbnail(at: path)
            }
        }
    }
}

// MARK: - Detail Panel Photo Page (非同期読み込み)
private struct DetailPanelPhotoPage: View {
    let path: String
    let index: Int
    let onTap: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .task {
            // 詳細パネルではやや大きめの画像が必要なのでサムネイルでなくフルを使用
            image = await PhotoStorage.loadThumbnail(at: path)
            isLoading = false
        }
    }
}
