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
    @ObservedObject private var monetization = MonetizationService.shared
    @StateObject private var weatherService = WeatherService()
    @StateObject private var appLockService = AppLockService.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("isDiaryTextHidden") private var isDiaryTextHidden: Bool = false
    @AppStorage("requiresDiaryOpenAuthentication") private var requiresDiaryOpenAuthentication: Bool = false
    @State private var showSettings = false
    @State private var showTaskManager = false
    @State private var showEventManager = false
    @State private var showTaskEditor = false
    @State private var showDiaryEditor = false
    @State private var showEventEditor = false
    @State private var showMemoEditor = false
    @State private var showAnalysisExport = false
    @State private var editingEvent: CalendarEvent?
    @State private var editingTask: Task?
    @State private var showLetterOpening = false
    @State private var letterToOpen: Letter?
    @State private var showSharedLetterOpening = false
    @State private var sharedLetterToOpen: LetterReceivingService.ReceivedLetter?
    @State private var receivedSharedLetters: [LetterReceivingService.ReceivedLetter] = []
    private let memoPlaceholder = "買い物リストや気づいたことを書いておけます"
    private let store: AppDataStore
    @State private var didAppear = false
    @State private var calendarSyncTrigger = 0
    @State private var showPaywall = false

    init(store: AppDataStore) {
        self.store = store
        _viewModel = StateObject(wrappedValue: TodayViewModel(store: store))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    letterSection
                    sharedLetterSection
                    eventsSection
                    //                todayTimelineSection
                    tasksSection
                    memoSection
                    habitsSection
                    healthSection
                    diarySection
                    
                    // Apple Weather Attribution (Required by WeatherKit)
                    if weatherService.currentWeather != nil {
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
                    }
                }
                .padding()
                .padding(.bottom, 80) // FABのための余白
            }
            .task {
                await weatherService.fetchWeather()
                // 共有手紙を取得
                await loadSharedLetters()
            }
            .onAppear {
                // タブ切り替え時に共有手紙を再読み込み（他画面で開封された可能性）
                _Concurrency.Task {
                    await loadSharedLetters()
                }
            }
            .task(id: calendarSyncTrigger) {
                await syncCalendarsIfNeeded()
            }
            .onChange(of: scenePhase, initial: false) { oldPhase, newPhase in
                if oldPhase != .active && newPhase == .active {
                    calendarSyncTrigger += 1
                    // 他の画面で開封された可能性があるので再読み込み
                    _Concurrency.Task {
                        await loadSharedLetters()
                    }
                }
            }
            .onChange(of: weatherService.currentWeather?.temperature) { _, _ in
                // 天気データをHealthSummaryに保存
                if let weather = weatherService.currentWeather {
                    store.updateWeather(
                        for: Date(),
                        condition: weather.conditionDescription,
                        high: weather.highTemperature,
                        low: weather.lowTemperature
                    )
                }
            }
            
            // FAB
            FloatingButton(iconName: "plus") {
                Button {
                    showTaskEditor = true
                } label: {
                    Label("タスクを追加", systemImage: "checkmark.circle")
                }
                Button {
                    showEventEditor = true
                } label: {
                    Label("予定を追加", systemImage: "calendar")
                }
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
                
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.primary)
                }
            }
        }
        .fullScreenCover(isPresented: $showLetterOpening, onDismiss: {
            // キャンセル時に状態をリセット
            letterToOpen = nil
        }) {
            Group {
                if let letter = letterToOpen {
                    LetterOpeningView(letter: letter) {
                        store.openLetter(letter.id)
                    }
                } else {
                    // フォールバック（通常は表示されない）
                    Color(uiColor: UIColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1))
                        .ignoresSafeArea()
                }
            }
        }
        .fullScreenCover(isPresented: $showSharedLetterOpening, onDismiss: {
            sharedLetterToOpen = nil
            // 開封後にリストを更新
            _Concurrency.Task {
                await loadSharedLetters()
            }
        }) {
            if let letter = sharedLetterToOpen {
                SharedLetterOpeningView(letter: letter)
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
                CalendarEventEditorView(event: event,
                                        onSave: { updated in store.updateCalendarEvent(updated) },
                                        onDelete: { store.deleteCalendarEvent(event.id) })
            }
        }
        .sheet(item: $editingTask) { task in
            NavigationStack {
                TaskEditorView(task: task,
                               defaultDate: task.startDate ?? task.endDate ?? viewModel.date,
                               onSave: { updated in store.updateTask(updated) },
                               onDelete: { store.deleteTasks(withIDs: [task.id]) })
            }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
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

    private func openDiaryEditor() {
        _Concurrency.Task { @MainActor in
            guard await authorizeDiaryAccessIfNeeded() else { return }
            showDiaryEditor = true
        }
    }

    private func authorizeDiaryAccessIfNeeded() async -> Bool {
        guard isDiaryTextHidden, requiresDiaryOpenAuthentication else { return true }
        return await appLockService.authenticateForSensitiveAction(reason: "日記を開くには認証が必要です")
    }

    private var header: some View {
        HStack(alignment: .top) {
            // 日付: 2行表示
            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.date.yearString)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(viewModel.date.monthDayWeekdayString)
                    .font(.largeTitle.bold())
            }
            
            Spacer()
            
            // 天気（コンパクト + 状態）
            if let weather = weatherService.currentWeather {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: weather.symbolName)
                            .font(.title2)
                            .symbolRenderingMode(.multicolor)
                        Text(weather.conditionDescription)
                            .font(.headline)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(weather.temperatureString)
                            .font(.largeTitle.bold())
                        if let highLow = weather.numericHighLowString {
                            Text(highLow)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if weatherService.isLoading {
                ProgressView()
            } else if weatherService.locationStatus == .notDetermined {
                Button {
                    weatherService.requestLocationPermission()
                } label: {
                    Image(systemName: "location.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.events) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(color(for: event.calendarName))
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(event.title)
                                            .font(.body.weight(.semibold))
                                        // リマインダー設定済みインジケーター
                                        if let reminderLabel = ReminderDisplay.eventReminderLabel(for: event) {
                                            HStack(spacing: 3) {
                                                Image(systemName: "bell.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Text(reminderLabel)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    Label(eventTimeLabel(event), systemImage: "clock")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 6) {
                                        if event.calendarName.isEmpty == false {
                                            Text(event.calendarName)
                                                .font(.caption2)
                                                .foregroundStyle(color(for: event.calendarName))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(color(for: event.calendarName).opacity(0.15), in: Capsule())
                                        }
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
                        }
                        if event.id != viewModel.events.last?.id {
                            Divider()
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    if viewModel.calendarAccessDenied {
                        Text("設定 > プライバシーとセキュリティ > カレンダーでlifelogへのアクセスを許可すると、外部カレンダーの予定が表示されます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        showEventManager = true
                    } label: {
                        Label("全てを表示", systemImage: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
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
                        HStack {
                            TaskRowView(task: task, onToggle: {
                                viewModel.toggleTask(task)
                            })
                            Spacer()
                            Button {
                                editingTask = task
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
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
                            HStack {
                                TaskRowView(task: task, onToggle: {
                                    viewModel.toggleTask(task)
                                })
                                Spacer()
                                Button {
                                    editingTask = task
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            if task.id != viewModel.completedTasksToday.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                Divider()
                HStack {
                    Button {
                        showTaskManager = true
                    } label: {
                        Label("全てを表示", systemImage: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    Spacer()
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
                            .foregroundStyle(.secondary)
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
        let visibleStatuses: [TodayViewModel.DailyHabitStatus] = monetization.isPremiumUnlocked
            ? viewModel.habitStatuses
            : Array(viewModel.habitStatuses.prefix(monetization.freeHabitLimit))
        let hiddenCount = max(0, viewModel.habitStatuses.count - visibleStatuses.count)
        return SectionCard(title: "習慣チェック") {
            if visibleStatuses.isEmpty {
                Text("本日分の習慣は登録されていません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(visibleStatuses) { status in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.toggleHabit(status.habit)
                            }
                        } label: {
                            HStack {
                                Label(status.habit.title, systemImage: status.habit.iconName)
                                    .foregroundStyle(Color(hex: status.habit.colorHex) ?? .accentColor)
                                Spacer()
                                AnimatedCheckmark(
                                    isCompleted: status.isCompleted,
                                    color: Color(hex: status.habit.colorHex) ?? .accentColor,
                                    size: 26
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if hiddenCount > 0 {
                PremiumLockCard(title: "非表示の習慣があります",
                                message: "無料プランでは\(monetization.freeHabitLimit)件まで表示されます。\(hiddenCount)件は非表示です。",
                                actionTitle: "プランを見る") {
                    showPaywall = true
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
                    if isDiaryTextHidden {
                        Text("日記本文は非表示です。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(entry.text)
                            .font(.body)
                            .lineLimit(3)
                    }
                } else {
                    Text("まだ記録がありません。今日感じたことを書き残しましょう。")
                        .foregroundStyle(.secondary)
                }
                Button {
                    openDiaryEditor()
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
    
    // MARK: - Letter to the Future
    
    @ViewBuilder
    private var letterSection: some View {
        let deliverableLetters = store.deliverableLetters()
        if monetization.canUseLetters == false {
            if !deliverableLetters.isEmpty {
                PremiumLockCard(title: "未来への手紙",
                                message: monetization.lettersMessage(),
                                actionTitle: "プランを見る") {
                    showPaywall = true
                }
            }
        } else if !deliverableLetters.isEmpty {
            VStack(spacing: 12) {
                ForEach(deliverableLetters) { letter in
                    letterCardView(for: letter)
                }
                
                // 設定から見れるメッセージ
                Text("✕で非表示にしても設定 > 未来への手紙 からいつでも読めます")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: letterToOpen) { _, newLetter in
                if newLetter != nil {
                    showLetterOpening = true
                }
            }
        }
    }
    
    @ViewBuilder
    private func letterCardView(for letter: Letter) -> some View {
        let isOpened = letter.status == .opened
        let bgColor: Color = isOpened ? Color(.systemGray6) : Color.orange.opacity(0.1)
        let borderColor: Color = isOpened ? Color.gray.opacity(0.2) : Color.orange.opacity(0.3)
        
        ZStack(alignment: .topTrailing) {
            Button {
                letterToOpen = letter
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: isOpened ? "envelope.open" : "envelope.fill")
                        .font(.title)
                        .foregroundStyle(isOpened ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isOpened ? "今日届いた手紙" : "📬 過去のあなたから手紙が届いています")
                            .font(.subheadline.weight(isOpened ? .medium : .semibold))
                            .foregroundStyle(.primary)
                        Text(isOpened ? "タップしてもう一度読む" : "タップして開封")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(bgColor))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderColor, lineWidth: 1))
            }
            .buttonStyle(.plain)
            
            // ✕ボタン（非表示にする）
            Button {
                withAnimation {
                    store.dismissLetterFromHome(letter.id)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.gray.opacity(0.5))
                    .background(Circle().fill(.white))
            }
            .offset(x: 8, y: -8)
        }
    }
    
    // MARK: - Shared Letter Section (大切な人からの手紙)
    
    @ViewBuilder
    private var sharedLetterSection: some View {
        // 未開封の共有手紙のみ表示
        let unreadLetters = receivedSharedLetters.filter { $0.status == "delivered" }
        if monetization.canUseLetters == false {
            if !unreadLetters.isEmpty {
                PremiumLockCard(title: "大切な人への手紙",
                                message: monetization.lettersMessage(),
                                actionTitle: "プランを見る") {
                    showPaywall = true
                }
            }
        } else if !unreadLetters.isEmpty {
            VStack(spacing: 12) {
                ForEach(unreadLetters) { letter in
                    sharedLetterCardView(for: letter)
                }
                
                // 設定から見れるメッセージ
                Text("✕で非表示にしても設定 > みんなの手紙 からいつでも読めます")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: sharedLetterToOpen) { _, newLetter in
                if newLetter != nil {
                    showSharedLetterOpening = true
                }
            }
        }
    }
    
    @ViewBuilder
    private func sharedLetterCardView(for letter: LetterReceivingService.ReceivedLetter) -> some View {
        let bgColor: Color = Color.blue.opacity(0.1)
        let borderColor: Color = Color.blue.opacity(0.3)
        
        ZStack(alignment: .topTrailing) {
            Button {
                sharedLetterToOpen = letter
            } label: {
                HStack(spacing: 16) {
                    Text(letter.senderEmoji)
                        .font(.title)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(letter.senderName)さんから手紙が届いています")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("タップして開封")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(bgColor))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderColor, lineWidth: 1))
            }
            .buttonStyle(.plain)
            
            // ✕ボタン（非表示にする）
            Button {
                withAnimation {
                    // 一覧から削除（実際には開封するまで消えない）
                    receivedSharedLetters.removeAll { $0.id == letter.id }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.gray.opacity(0.5))
                    .background(Circle().fill(.white))
            }
            .offset(x: 8, y: -8)
        }
    }
    
    private func loadSharedLetters() async {
        do {
            receivedSharedLetters = try await LetterReceivingService.shared.getReceivedLetters()
        } catch {
            print("共有手紙の取得に失敗: \(error.localizedDescription)")
        }
    }
}
