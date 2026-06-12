//
//  JournalView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI
import UIKit
import MapKit
import Combine

private enum ReviewContentMode: String, CaseIterable, Identifiable {
    case diary = "日記"
    case map = "地図"

    var id: String { rawValue }
}

struct JournalView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var monetization = MonetizationService.shared
    @ObservedObject private var appLockService = AppLockService.shared
    @AppStorage("isDiaryTextHidden") private var isDiaryTextHidden: Bool = false
    @AppStorage("requiresDiaryOpenAuthentication") private var requiresDiaryOpenAuthentication: Bool = false
    @AppStorage("isMemoTextHidden") private var isMemoTextHidden: Bool = false
    @AppStorage("requiresMemoOpenAuthentication") private var requiresMemoOpenAuthentication: Bool = false
    private let store: AppDataStore
    @StateObject private var viewModel: JournalViewModel
    private let monthPagerHeight: CGFloat = 700
    private let monthPagerRadius = 3
    private let calendarGridSpacing: CGFloat = 4
    private let calendarCellHeight: CGFloat = 88
    private let calendarCellCornerRadius: CGFloat = 10
    private let calendarCellTopPadding: CGFloat = 4
    private let calendarCellRowSpacing: CGFloat = 2
    private let calendarCellDateRowHeight: CGFloat = 18
    private let calendarPreviewRowHeight: CGFloat = 14
    private let calendarPreviewRowCornerRadius: CGFloat = 4
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
    private let backgroundReviewPhotoPrefetchLimit = 24
    @State private var showPaywall = false
    @State private var premiumAlertMessage: String?

    // detailPager は ~15 アンカー分の calendarSnapshot(for:) を毎レンダーで再計算するため、
    // 同一データに対する重複スキャンをキャッシュで防ぐ。キーは startOfDay。
    // 無効化はストアのデータ変更時（store.objectWillChange）にのみ行う。レンダーや
    // ページ切替では再計算しないため、表示内容は従来と完全に一致する。
    @State private var snapshotCache: [Date: CalendarDetailSnapshot] = [:]
    // reviewMapGroups は store.diaryEntries 全件から毎レンダー再構築するため、period 単位でメモ化する。
    // 無効化条件は snapshotCache と同じ（ストアのデータ変更時のみ）。
    @State private var reviewMapGroupsCache: [ReviewMapPeriod: [ReviewLocationGroup]] = [:]
    // weekTimeline は 7 日分の timelineItems(for:) を毎レンダー再計算するため、startOfDay 単位でキャッシュする。
    // 無効化条件は上記と同じ。
    @State private var weekTimelineItemsCache: [Date: [JournalViewModel.TimelineItem]] = [:]

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
                                 initialIndex: reviewPhotoViewerIndex,
                                 onIndexChanged: { newIndex in
                                     reviewPhotoViewerIndex = newIndex
                                 })
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
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
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
        .alert("プレミアム機能", isPresented: Binding(
            get: { premiumAlertMessage != nil },
            set: { if $0 == false { premiumAlertMessage = nil } }
        )) {
            Button("プランを見る") {
                showPaywall = true
            }
            Button("あとで", role: .cancel) { }
        } message: {
            Text(premiumAlertMessage ?? "")
        }
        .onReceive(store.objectWillChange) { _ in
            // ストアのデータが変化した時のみ、各種スナップショットキャッシュを破棄する。
            // これにより calendarSnapshot / reviewMapGroups / weekTimeline の計算は
            // 「データ変更ごとに最大1回」に抑えられ、毎レンダーの全件スキャンを排除する。
            // objectWillChange は変更の「直前」に発火するが、キャッシュは次回参照時に
            // 最新ストアから再計算されるため、表示が古くなることはない。
            snapshotCache.removeAll()
            reviewMapGroupsCache.removeAll()
            weekTimelineItemsCache.removeAll()
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
        // monthAnchor の onChange は1つに統合してある。同じ値に対する
        // .onChange を複数並べると SwiftUI がどれを呼ぶか保証されないため、
        // スケジュール側(ページャ同期・外部カレンダー同期)とレビュー側
        // (選択日の追従)をここでまとめて処理する。
        .onChange(of: viewModel.monthAnchor) { _, newAnchor in
            if viewModel.displayMode == .month {
                ensureMonthPagerIncludes(date: newAnchor)
                _Concurrency.Task {
                    await viewModel.syncExternalCalendarsIfNeeded(anchorDate: newAnchor)
                }
                if calendarMode != .review {
                    scheduleDeferredPreload()
                }
            }
            if calendarMode == .review {
                // selectedReviewDate が nil の場合 reviewMapGroups(.month) は monthAnchor を
                // 月境界の基準にフォールバックするため、月移動時もメモ化結果を破棄する。
                reviewMapGroupsCache.removeAll()
                syncReviewSelection(to: newAnchor)
            }
        }
        .onChange(of: calendarMode) { _, newMode in
            if newMode == .review {
                viewModel.displayMode = .month
                selectedReviewDate = viewModel.selectedDate
                reviewPhotoIndex = preferredPhotoIndex(for: store.entry(for: selectedReviewDate ?? viewModel.selectedDate))
                reviewContentMode = .diary
                prefetchPhotosForMonths(around: viewModel.monthAnchor, monthRadius: 0)
            }
        }
        .onChange(of: reviewContentMode) { _, newMode in
            guard newMode == .map else { return }
            guard monetization.canUseReviewMap else {
                reviewContentMode = .diary
                premiumAlertMessage = monetization.reviewMapMessage()
                return
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
        .onChange(of: selectedReviewDate) { _, newDate in
            // reviewMapGroups(.month) は selectedReviewDate を月境界の基準に使うため、
            // 選択日が変わったらメモ化結果を破棄する（ストア変更以外の無効化要因）。
            reviewMapGroupsCache.removeAll()
            reviewPhotoIndex = preferredPhotoIndex(for: store.entry(for: newDate ?? viewModel.monthAnchor))
        }
    }

    /// レビューモードで月を移動したとき、選択日が表示中の月から外れていれば
    /// 月初(アンカー)に追従させる。
    private func syncReviewSelection(to newAnchor: Date) {
        let selectionIsOutsideMonth = selectedReviewDate.map {
            Calendar.current.isDate($0, equalTo: newAnchor, toGranularity: .month) == false
        } ?? true
        guard selectionIsOutsideMonth else { return }
        selectedReviewDate = newAnchor
        reviewPhotoIndex = preferredPhotoIndex(for: store.entry(for: newAnchor))
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
                if calendarMode == .schedule || reviewContentMode == .diary {
                    if activeDisplayMode == .month {
                        weekdayHeader
                            .padding(.horizontal, 4)
                    } else if activeDisplayMode == .week {
                        weekdayHeader
                            .padding(.horizontal, 4)
                    }
                    calendarSwitcher
                }
                if calendarMode == .schedule {
                    contentArea
                    calendarLegend
                } else {
                    if reviewContentMode == .diary {
                        reviewDetail
                    } else if monetization.canUseReviewMap {
                        reviewMap
                    } else {
                        PremiumLockCard(title: "振り返り地図",
                                        message: monetization.reviewMapMessage(),
                                        actionTitle: "プランを見る") {
                            showPaywall = true
                        }
                    }
                }
                if viewModel.calendarAccessDenied {
                    Text("設定 > プライバシーとセキュリティ > カレンダーでlifelifyへのアクセスを許可すると外部カレンダーの予定が表示されます。")
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
            Text(ReviewContentMode.diary.rawValue).tag(ReviewContentMode.diary)
            if monetization.canUseReviewMap {
                Text(ReviewContentMode.map.rawValue).tag(ReviewContentMode.map)
            } else {
                Text("地図🔒").tag(ReviewContentMode.map)
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
            // スクロールアニメーション完了後にページャー拡張
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                extendMonthPagerIfNeeded(at: newSelection)
            }
            
            // 振り返りモードの場合、前後月含めてプリフェッチ
            if calendarMode == .review {
                prefetchPhotosForMonths(around: anchor)
            }
        }
    }

    private var monthGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: calendarGridSpacing), count: 7)
    }

    private func monthCalendar(for anchor: Date) -> some View {
        let columns = monthGridColumns
        let itemLimit = 4
        let days = viewModel.calendarDays(for: anchor)
        let weekLayouts = monthCalendarMultiDayLayouts(days: days, itemLimit: itemLimit)
        return LazyVGrid(columns: columns, spacing: calendarGridSpacing) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let weekIndex = index / 7
                let dayIndex = index % 7
                let layout = weekLayouts.indices.contains(weekIndex) ? weekLayouts[weekIndex] : .empty
                let multiDayState = layout.dayStates.indices.contains(dayIndex) ? layout.dayStates[dayIndex] : .empty
                monthDayCell(day, itemLimit: itemLimit, multiDayState: multiDayState)
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                monthMultiDayOverlay(weekLayouts: weekLayouts, gridWidth: geometry.size.width)
            }
            .allowsHitTesting(false)
        }
        // .animation removed: グリッド全体へのアニメーション伝播を防止（スクロールのカクつき対策）
    }

    @ViewBuilder
    private func monthDayCell(_ day: JournalViewModel.CalendarDay,
                              itemLimit: Int,
                              multiDayState: CalendarDayMultiDayState) -> some View {
        let previews = dayPreviewItems(events: day.events, tasks: day.tasks, on: day.date)
        let rowContents = calendarCellRowContents(previews: previews,
                                                  itemLimit: itemLimit,
                                                  multiDayState: multiDayState)
        VStack(alignment: .leading, spacing: 2) {
            // Date fixed in top-left
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(calendarDateTextColor(for: day.date,
                                                       isWithinDisplayedMonth: day.isWithinDisplayedMonth))
                .padding(.horizontal, 4)  // Date gets its own padding
                .frame(height: calendarCellDateRowHeight, alignment: .leading)
            
            // Items below the date
            ForEach(Array(rowContents.enumerated()), id: \.offset) { _, rowContent in
                calendarCellRowView(rowContent)
            }
        }
        .padding(.top, calendarCellTopPadding)
        // Remove .padding(.horizontal, 4) from VStack
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: calendarCellHeight)
        // Use a mask that allows horizontal overflow (for connected bars)
        // but clips vertical overflow (to keep fixed height).
        // Padding -20 extends the mask horizontally by 20pt on each side.
        .mask(Rectangle().padding(.horizontal, -20))
        .background(
            RoundedRectangle(cornerRadius: calendarCellCornerRadius)
                .fill(day.isToday ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: calendarCellCornerRadius)
                .stroke(Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .center) {
            if viewModel.selectedDate.isSameDay(as: day.date) {
                RoundedRectangle(cornerRadius: calendarCellCornerRadius)
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
            // スクロールアニメーション完了後にページャー拡張
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                extendWeekPagerIfNeeded(at: newSelection)
            }
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
        let columns = Array(repeating: GridItem(.flexible(), spacing: calendarGridSpacing), count: 7)
        let multiDayLayout = weekCalendarMultiDayLayout(dates: dates, itemLimit: itemLimit)
        return LazyVGrid(columns: columns, spacing: calendarGridSpacing) {
            ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                let multiDayState = multiDayLayout.dayStates.indices.contains(index) ? multiDayLayout.dayStates[index] : .empty
                weekDayCell(date, itemLimit: itemLimit, multiDayState: multiDayState)
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                weekMultiDayOverlay(layout: multiDayLayout, gridWidth: geometry.size.width)
            }
            .allowsHitTesting(false)
        }
        // .animation removed: グリッド全体へのアニメーション伝播を防止（スクロールのカクつき対策）
    }

    @ViewBuilder
    private func weekDayCell(_ date: Date,
                             itemLimit: Int,
                             multiDayState: CalendarDayMultiDayState) -> some View {
        let previews = dayPreviewItems(for: date)
        let rowContents = calendarCellRowContents(previews: previews,
                                                  itemLimit: itemLimit,
                                                  multiDayState: multiDayState)
        VStack(alignment: .leading, spacing: 2) {
            // Date fixed in top-left
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(calendarDateTextColor(for: date))
                .padding(.horizontal, 4)  // Date gets its own padding
                .frame(height: calendarCellDateRowHeight, alignment: .leading)
            
            // Items below the date
            ForEach(Array(rowContents.enumerated()), id: \.offset) { _, rowContent in
                calendarCellRowView(rowContent)
            }
        }
        .padding(.top, calendarCellTopPadding)
        // Remove .padding(.horizontal, 4) from VStack
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: calendarCellHeight)
        // Mask allowing horizontal overflow to connect bars
        .mask(Rectangle().padding(.horizontal, -20))
        .background(
            RoundedRectangle(cornerRadius: calendarCellCornerRadius)
                .fill(date.isSameDay(as: Date()) ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: calendarCellCornerRadius)
                .stroke(Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .center) {
            if date.startOfDay == viewModel.selectedDate.startOfDay {
                RoundedRectangle(cornerRadius: calendarCellCornerRadius)
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

    private func calendarDateTextColor(for date: Date, isWithinDisplayedMonth: Bool = true) -> Color {
        guard isWithinDisplayedMonth, Calendar.current.isDateInWeekend(date) == false else {
            return .secondary
        }
        return .primary
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
    private func prefetchPhotosForMonths(
        around anchor: Date,
        monthRadius: Int = 1,
        maxPaths: Int? = nil,
        background: Bool = false
    ) {
        guard monthRadius >= 0 else { return }
        let calendar = Calendar.current
        var allPaths: [String] = []
        var seen = Set<String>()
        
        // 前月・今月・次月の3ヶ月分
        for offset in (-monthRadius...monthRadius) {
            if let monthDate = calendar.date(byAdding: .month, value: offset, to: anchor) {
                let days = viewModel.calendarDays(for: monthDate)
                for path in days.compactMap({ reviewThumbnailPath(for: $0.diary) }) where seen.insert(path).inserted {
                    allPaths.append(path)
                }
            }
        }

        if let maxPaths {
            allPaths = Array(allPaths.prefix(maxPaths))
        }
        
        if !allPaths.isEmpty {
            if background {
                PhotoStorage.prefetchThumbnailsInBackground(paths: allPaths)
            } else {
                PhotoStorage.prefetchThumbnails(paths: allPaths)
            }
        }
    }

    private func reviewThumbnailPath(for diary: DiaryEntry?) -> String? {
        guard let diary else { return nil }
        return diary.favoritePhotoPath ?? diary.photoPaths.first
    }

    private var reviewDetail: some View {
        VStack(spacing: 12) {
            let targetDate = selectedReviewDate ?? viewModel.monthAnchor
            reviewDetailCard(for: targetDate)
        }
    }

    private var reviewMap: some View {
        ReviewMapView(groups: reviewMapGroups(for: reviewMapPeriod),
                      orderedTags: store.locationVisitTagDefinitions
                        .sorted { $0.sortOrder < $1.sortOrder }
                        .map(\.name),
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

    private func reviewMapGroups(for period: ReviewMapPeriod) -> [ReviewLocationGroup] {
        // diaryEntries 全件からの再構築はストア変更まで不変なので period 単位でメモ化する。
        if let cached = reviewMapGroupsCache[period] {
            return cached
        }
        let groups = computeReviewMapGroups(for: period)
        reviewMapGroupsCache[period] = groups
        return groups
    }

    private func computeReviewMapGroups(for period: ReviewMapPeriod) -> [ReviewLocationGroup] {
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
                                  mapItemURL: nil,
                                  photoPaths: [])
                ]
            } else {
                locations = entry.locations
            }
            for location in locations {
                results.append(ReviewLocationEntry(date: entryDate,
                                                   location: location,
                                                   photoPaths: location.photoPaths,
                                                   tags: location.visitTags))
            }
        }
        var grouped: [String: ReviewLocationGroupBuilder] = [:]
        for entry in results {
            let key = ReviewLocationGroupBuilder.makeKey(for: entry.location)
            if var existing = grouped[key] {
                existing.add(date: entry.date, photoPaths: entry.photoPaths, tags: entry.tags)
                grouped[key] = existing
            } else {
                grouped[key] = ReviewLocationGroupBuilder(location: entry.location,
                                                          date: entry.date,
                                                          photoPaths: entry.photoPaths,
                                                          tags: entry.tags)
            }
        }
        return grouped.values
            .map { ReviewLocationGroup(id: $0.id, location: $0.location, visits: $0.visits) }
            .sorted { $0.latestDate > $1.latestDate }
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
        return ReviewDetailPanel(
            date: date,
            store: store,
            diary: diary,
            isDiaryTextHidden: isDiaryTextHidden,
            photoPaths: photoPaths,
            preferredIndex: preferredIndex,
            reviewPhotoViewerIndex: $reviewPhotoViewerIndex,
            pendingPhotoViewerDate: $pendingPhotoViewerDate,
            showingDetailPanel: $showingDetailPanel,
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
                            items: weekTimelineItems(for: date),
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

    // 週タイムラインは 7 日分を毎レンダー再計算するため、startOfDay 単位でキャッシュする。
    // タスク種別は週タイムラインに表示しない仕様なのでフィルタ後の結果を保持する。
    // 無効化はストア変更時（store.objectWillChange）に行うため表示内容は不変。
    private func weekTimelineItems(for date: Date) -> [JournalViewModel.TimelineItem] {
        let cacheKey = date.startOfDay
        if let cached = weekTimelineItemsCache[cacheKey] {
            return cached
        }
        let items = viewModel.timelineItems(for: date).filter { $0.kind != .task }
        weekTimelineItemsCache[cacheKey] = items
        return items
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
        _Concurrency.Task { @MainActor in
            guard await authorizeDiaryAccessIfNeeded() else { return }
            let targetDate = date.startOfDay
            viewModel.selectedDate = targetDate
            let fromReview = calendarMode == .review
            isDiaryOpeningFromReview = showingDetailPanel && fromReview
            if showingDetailPanel {
                pendingDiaryDate = targetDate
                showingDetailPanel = false
            } else {
                pendingDiaryDate = nil
                diaryEditorDate = targetDate
            }
        }
    }

    private func authorizeDiaryAccessIfNeeded() async -> Bool {
        guard isDiaryTextHidden, requiresDiaryOpenAuthentication else { return true }
        return await appLockService.authenticateForSensitiveAction(reason: "日記を開くには認証が必要です")
    }

    private func openMemoEditor() {
        _Concurrency.Task { @MainActor in
            guard await authorizeMemoAccessIfNeeded() else { return }
            showMemoEditor = true
        }
    }

    private func authorizeMemoAccessIfNeeded() async -> Bool {
        guard isMemoTextHidden, requiresMemoOpenAuthentication else { return true }
        return await appLockService.authenticateForSensitiveAction(reason: "メモを開くには認証が必要です")
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
        // 同一日のスナップショットはストア変更まで不変なので、キャッシュ命中時は再スキャンしない。
        let cacheKey = date.startOfDay
        if let cached = snapshotCache[cacheKey] {
            return cached
        }
        let snapshot = computeCalendarSnapshot(for: date)
        snapshotCache[cacheKey] = snapshot
        return snapshot
    }

    private func computeCalendarSnapshot(for date: Date) -> CalendarDetailSnapshot {
        let events = store.events(on: date)
        // 詳細シートでは開始〜終了日の範囲内のタスクを表示
        let sortedTasks = viewModel.tasksInRange(on: date).sorted(by: calendarTaskSort)
        let pendingTasks = sortedTasks.filter { $0.isCompleted == false }
        let completedTasks = sortedTasks.filter(\.isCompleted)
        let statuses = store.habits
            .filter { !$0.isArchived && $0.schedule.isActive(on: date) }
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
                Group {
                    if calendarMode == .schedule {
                        CalendarDetailPanel(snapshot: snapshot,
                                            store: store,
                                            isDiaryTextHidden: isDiaryTextHidden,
                                            includeAddButtons: includeAddButtons,
                                            showHeader: showHeader,
                                            onToggleTask: { toggleTask($0) },
                                            onToggleHabit: { toggleHabit($0, on: snapshot.date) },
                                            onOpenDiary: { openDiaryEditor(for: $0) })
                    } else {
                        reviewDetailCard(for: anchor)
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
        .frame(minHeight: calendarMode == .schedule ? minHeight : nil)
        .onChange(of: detailPagerSelection) { _, newSelection in
            guard detailPagerAnchors.indices.contains(newSelection) else { return }
            let date = detailPagerAnchors[newSelection]
            // スクロールアニメーション完了後に副作用を実行
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if date.startOfDay != viewModel.selectedDate.startOfDay {
                    isSyncingDetailPager = true
                    viewModel.selectedDate = date
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isSyncingDetailPager = false
                    }
                }
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

    private func previewLabel(for item: DayPreviewItem) -> String {
        item.title
    }
    
    private func calendarCellRowContents(previews: [DayPreviewItem],
                                         itemLimit: Int,
                                         multiDayState: CalendarDayMultiDayState) -> [CalendarCellRowContent] {
        guard itemLimit > 0 else { return [] }

        let regularItems = previews.filter { item in
            !(item.kind == .event && item.isMultiDayEvent)
        }

        var rows = Array(repeating: CalendarCellRowContent.empty, count: itemLimit)
        var availableRows: [Int] = []

        for rowIndex in 0..<itemLimit {
            let isOccupiedByVisibleMultiDay = rowIndex < multiDayState.visibleLaneCount &&
                multiDayState.occupiedVisibleLanes.contains(rowIndex)
            if isOccupiedByVisibleMultiDay {
                rows[rowIndex] = .multiDayPlaceholder
            } else {
                availableRows.append(rowIndex)
            }
        }

        guard availableRows.isEmpty == false else { return rows }

        let needsOverflowRow = multiDayState.hiddenMultiDayCount > 0 || regularItems.count > availableRows.count
        let displayedRegularCount: Int
        let overflowCount: Int

        if needsOverflowRow {
            let regularCapacity = max(0, availableRows.count - 1)
            displayedRegularCount = min(regularItems.count, regularCapacity)
            overflowCount = multiDayState.hiddenMultiDayCount + max(0, regularItems.count - displayedRegularCount)
        } else {
            displayedRegularCount = regularItems.count
            overflowCount = 0
        }

        for (offset, item) in regularItems.prefix(displayedRegularCount).enumerated() {
            rows[availableRows[offset]] = .item(item)
        }

        if overflowCount > 0, availableRows.indices.contains(displayedRegularCount) {
            rows[availableRows[displayedRegularCount]] = .overflow(overflowCount)
        }

        return rows
    }

    @ViewBuilder
    private func calendarCellRowView(_ content: CalendarCellRowContent) -> some View {
        switch content {
        case .multiDayPlaceholder, .empty:
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: calendarPreviewRowHeight)
        case .overflow(let count):
            Text("+\(count)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: calendarPreviewRowHeight, alignment: .center)
        case .item(let item):
            if item.kind == .event {
                singleDayEventBarView(item: item)
            } else {
                CalendarPreviewText(text: previewLabel(for: item))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(item.color.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: calendarPreviewRowCornerRadius))
                    .clipped()
                    .frame(height: calendarPreviewRowHeight, alignment: .center)
            }
        }
    }

    private func weekCalendarMultiDayLayout(dates: [Date], itemLimit: Int) -> CalendarWeekMultiDayLayout {
        var uniqueEvents: [UUID: CalendarEvent] = [:]
        for date in dates {
            for event in store.events(on: date) where isMultiDayEvent(event) {
                uniqueEvents[event.id] = event
            }
        }
        return buildWeekMultiDayLayout(weekDates: dates,
                                       events: Array(uniqueEvents.values),
                                       itemLimit: itemLimit)
    }

    private func monthCalendarMultiDayLayouts(days: [JournalViewModel.CalendarDay],
                                              itemLimit: Int) -> [CalendarWeekMultiDayLayout] {
        guard days.isEmpty == false else { return [] }

        var layouts: [CalendarWeekMultiDayLayout] = []
        for startIndex in stride(from: 0, to: days.count, by: 7) {
            let endIndex = min(startIndex + 7, days.count)
            guard endIndex - startIndex == 7 else { continue }
            let weekDays = Array(days[startIndex..<endIndex])

            var uniqueEvents: [UUID: CalendarEvent] = [:]
            for day in weekDays {
                for event in day.events where isMultiDayEvent(event) {
                    uniqueEvents[event.id] = event
                }
            }

            layouts.append(
                buildWeekMultiDayLayout(weekDates: weekDays.map(\.date),
                                        events: Array(uniqueEvents.values),
                                        itemLimit: itemLimit)
            )
        }
        return layouts
    }

    private func buildWeekMultiDayLayout(weekDates: [Date],
                                         events: [CalendarEvent],
                                         itemLimit: Int) -> CalendarWeekMultiDayLayout {
        let calendar = Calendar.current
        guard weekDates.count == 7,
              let firstWeekDate = weekDates.first,
              let lastWeekDate = weekDates.last
        else {
            return .empty
        }

        let weekStart = calendar.startOfDay(for: firstWeekDate)
        let weekLastDay = calendar.startOfDay(for: lastWeekDate)
        guard let weekEndExclusive = calendar.date(byAdding: .day, value: 1, to: weekLastDay) else {
            return .empty
        }

        struct Candidate {
            let event: CalendarEvent
            let startColumn: Int
            let endColumn: Int
            let continuesBeforeWeek: Bool
            let continuesAfterWeek: Bool
        }

        var candidates: [Candidate] = []
        for event in events {
            guard event.startDate < weekEndExclusive, event.endDate > weekStart else { continue }

            let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
            let eventStartDay = calendar.startOfDay(for: event.startDate)
            let rawEventEndDay = calendar.startOfDay(for: adjustedEnd)
            let eventEndDay = max(rawEventEndDay, eventStartDay)
            let visibleStartDay = max(eventStartDay, weekStart)
            let visibleEndDay = min(eventEndDay, weekLastDay)

            guard visibleStartDay <= visibleEndDay else { continue }

            let startColumn = calendar.dateComponents([.day], from: weekStart, to: visibleStartDay).day ?? 0
            let endColumn = calendar.dateComponents([.day], from: weekStart, to: visibleEndDay).day ?? 0
            guard (0..<7).contains(startColumn), (0..<7).contains(endColumn), startColumn <= endColumn else { continue }

            candidates.append(
                Candidate(event: event,
                          startColumn: startColumn,
                          endColumn: endColumn,
                          continuesBeforeWeek: eventStartDay < weekStart,
                          continuesAfterWeek: eventEndDay > weekLastDay)
            )
        }

        if candidates.isEmpty {
            return .empty
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.startColumn != rhs.startColumn {
                return lhs.startColumn < rhs.startColumn
            }
            let lhsSpan = lhs.endColumn - lhs.startColumn
            let rhsSpan = rhs.endColumn - rhs.startColumn
            if lhsSpan != rhsSpan {
                return lhsSpan > rhsSpan
            }
            if lhs.event.isAllDay != rhs.event.isAllDay {
                return lhs.event.isAllDay && rhs.event.isAllDay == false
            }
            if lhs.event.startDate != rhs.event.startDate {
                return lhs.event.startDate < rhs.event.startDate
            }
            return lhs.event.title < rhs.event.title
        }

        let maxVisibleLanes = max(0, itemLimit - 1)
        var laneEndColumns: [Int] = []
        var visibleSegments: [CalendarWeekMultiDaySegment] = []
        var occupiedVisibleLanesByDay = Array(repeating: Set<Int>(), count: 7)
        var hiddenCountByDay = Array(repeating: 0, count: 7)

        for candidate in sortedCandidates {
            let assignedLane: Int
            if let lane = laneEndColumns.firstIndex(where: { candidate.startColumn > $0 }) {
                assignedLane = lane
                laneEndColumns[lane] = candidate.endColumn
            } else {
                assignedLane = laneEndColumns.count
                laneEndColumns.append(candidate.endColumn)
            }

            if assignedLane < maxVisibleLanes {
                for dayIndex in candidate.startColumn...candidate.endColumn {
                    occupiedVisibleLanesByDay[dayIndex].insert(assignedLane)
                }
                visibleSegments.append(
                    CalendarWeekMultiDaySegment(
                        id: "\(weekStart.timeIntervalSince1970)-\(candidate.event.id.uuidString)-\(assignedLane)",
                        eventID: candidate.event.id,
                        title: candidate.event.title,
                        color: CategoryPalette.color(for: candidate.event.calendarName),
                        lane: assignedLane,
                        startColumn: candidate.startColumn,
                        endColumn: candidate.endColumn,
                        continuesBeforeWeek: candidate.continuesBeforeWeek,
                        continuesAfterWeek: candidate.continuesAfterWeek
                    )
                )
            } else {
                for dayIndex in candidate.startColumn...candidate.endColumn {
                    hiddenCountByDay[dayIndex] += 1
                }
            }
        }

        let visibleLaneCount = min(laneEndColumns.count, maxVisibleLanes)
        let dayStates = (0..<7).map { index in
            CalendarDayMultiDayState(visibleLaneCount: visibleLaneCount,
                                     occupiedVisibleLanes: occupiedVisibleLanesByDay[index],
                                     hiddenMultiDayCount: hiddenCountByDay[index])
        }

        return CalendarWeekMultiDayLayout(visibleLaneCount: visibleLaneCount,
                                          dayStates: dayStates,
                                          segments: visibleSegments)
    }

    private func monthMultiDayOverlay(weekLayouts: [CalendarWeekMultiDayLayout], gridWidth: CGFloat) -> some View {
        multiDayOverlay(weekLayouts: weekLayouts, gridWidth: gridWidth)
    }

    private func weekMultiDayOverlay(layout: CalendarWeekMultiDayLayout, gridWidth: CGFloat) -> some View {
        multiDayOverlay(weekLayouts: [layout], gridWidth: gridWidth)
    }

    @ViewBuilder
    private func multiDayOverlay(weekLayouts: [CalendarWeekMultiDayLayout], gridWidth: CGFloat) -> some View {
        let cellWidth = calendarGridCellWidth(for: gridWidth)
        if cellWidth > 0 {
            ZStack(alignment: .topLeading) {
                ForEach(Array(weekLayouts.enumerated()), id: \.offset) { weekIndex, layout in
                    ForEach(layout.segments) { segment in
                        let spanLength = segment.endColumn - segment.startColumn + 1
                        let x = CGFloat(segment.startColumn) * (cellWidth + calendarGridSpacing)
                        let y = CGFloat(weekIndex) * (calendarCellHeight + calendarGridSpacing) + multiDayOverlayRowY(lane: segment.lane)
                        let width = CGFloat(spanLength) * cellWidth + CGFloat(max(0, spanLength - 1)) * calendarGridSpacing

                        multiDayOverlayBarView(segment: segment)
                            .frame(width: width, height: calendarPreviewRowHeight, alignment: .leading)
                            .offset(x: x, y: y)
                    }
                }
            }
        }
    }

    private func calendarGridCellWidth(for totalWidth: CGFloat) -> CGFloat {
        let totalSpacing = calendarGridSpacing * 6
        guard totalWidth > totalSpacing else { return 0 }
        return (totalWidth - totalSpacing) / 7
    }

    private func multiDayOverlayRowY(lane: Int) -> CGFloat {
        calendarCellTopPadding +
        calendarCellDateRowHeight +
        calendarCellRowSpacing +
        CGFloat(lane) * (calendarPreviewRowHeight + calendarCellRowSpacing)
    }

    @ViewBuilder
    private func singleDayEventBarView(item: DayPreviewItem) -> some View {
        CalendarPreviewText(text: item.title)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 3)
            .padding(.vertical, 1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: calendarPreviewRowCornerRadius)
                    .fill(item.color.opacity(0.3))
            )
            .clipped()
            .frame(height: calendarPreviewRowHeight, alignment: .center)
    }

    @ViewBuilder
    private func multiDayOverlayBarView(segment: CalendarWeekMultiDaySegment) -> some View {
        let leadingRadius: CGFloat = segment.continuesBeforeWeek ? 0 : calendarPreviewRowCornerRadius
        let trailingRadius: CGFloat = segment.continuesAfterWeek ? 0 : calendarPreviewRowCornerRadius
        let showTitle = segment.continuesBeforeWeek == false

        HStack(spacing: 0) {
            if showTitle {
                CalendarPreviewText(text: segment.title)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Keep bar thickness even when the repeated label is hidden.
                CalendarPreviewText(text: " ")
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0)
            }
        }
            .padding(.horizontal, 3)
            .padding(.vertical, 1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: leadingRadius,
                    bottomLeadingRadius: leadingRadius,
                    bottomTrailingRadius: trailingRadius,
                    topTrailingRadius: trailingRadius
                )
                .fill(segment.color.opacity(0.3))
            )
            .clipped()
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
            await viewModel.syncExternalCalendarsIfNeeded(
                force: true,
                anchorDate: viewModel.monthAnchor,
                allowPermissionPrompt: true
            )
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
            try? await _Concurrency.Task.sleep(nanoseconds: 250_000_000)
            viewModel.preloadMonths(around: viewModel.monthAnchor, radius: 1)
            // まず当月は優先先読みして、振り返り切り替え直後の表示を速くする
            prefetchPhotosForMonths(around: viewModel.monthAnchor, monthRadius: 0)
            // 周辺月は軽量先読みで徐々に温める
            prefetchPhotosForMonths(
                around: viewModel.monthAnchor,
                monthRadius: 1,
                maxPaths: backgroundReviewPhotoPrefetchLimit,
                background: true
            )
        }
    }

    @ToolbarContentBuilder
    private var journalToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                openMemoEditor()
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

private enum ScrollTarget: String {
    case detailPanel
}
