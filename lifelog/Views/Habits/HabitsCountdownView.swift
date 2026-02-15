//
//  HabitsCountdownView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct HabitsCountdownView: View {
    @StateObject private var habitsViewModel: HabitsViewModel
    @StateObject private var anniversaryViewModel: AnniversaryViewModel
    @ObservedObject private var monetization = MonetizationService.shared
    private let store: AppDataStore
    var resetTrigger: Int = 0
    @State private var showHabitEditor = false
    @State private var showAnniversaryEditor = false
    @State private var editingHabit: Habit?
    @State private var editingAnniversary: Anniversary?
    @State private var displayMode: DisplayMode = .habits
    @State private var selectedHabitForDetail: Habit?
    @State private var selectedSummaryDate: Date?
    @State private var showSettings = false
    @State private var showHabitReorder = false
    @State private var showAnniversaryReorder = false
    @State private var premiumAlertMessage: String?
    @State private var showPaywall = false
    @AppStorage("githubUsername") private var githubUsername: String = ""
    @StateObject private var githubService = GitHubService.shared

    init(store: AppDataStore, resetTrigger: Int = 0) {
        self.store = store
        self.resetTrigger = resetTrigger
        _habitsViewModel = StateObject(wrappedValue: HabitsViewModel(store: store))
        _anniversaryViewModel = StateObject(wrappedValue: AnniversaryViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                yearlyHeatmapSection
                modePicker
                switch displayMode {
                case .habits:
                    habitsSection
                case .countdown:
                    anniversarySection
                case .github:
                    GitHubContributionsView()
                }
            }
            .padding()
        }
        .navigationTitle("習慣とカウントダウン")
        .sheet(isPresented: $showHabitEditor) {
            NavigationStack {
                HabitEditorView { habit in
                    habitsViewModel.addHabit(habit)
                }
            }
        }
        .sheet(isPresented: $showAnniversaryEditor) {
            NavigationStack {
                AnniversaryEditorView { anniversary in
                    anniversaryViewModel.add(anniversary)
                }
            }
        }
        .sheet(item: $editingHabit) { habit in
            NavigationStack {
                HabitEditorView(habit: habit,
                                onSave: { updated in habitsViewModel.updateHabit(updated) },
                                onDelete: { habitsViewModel.deleteHabit(habit) })
            }
        }
        .sheet(item: $editingAnniversary) { anniversary in
            NavigationStack {
                AnniversaryEditorView(anniversary: anniversary,
                                      onSave: { updated in anniversaryViewModel.update(updated) },
                                      onDelete: { anniversaryViewModel.delete(anniversary) })
            }
        }
        .sheet(isPresented: Binding(get: { selectedSummaryDate != nil },
                                    set: { if $0 == false { selectedSummaryDate = nil } })) {
            if let date = selectedSummaryDate,
               let summary = habitsViewModel.summary(for: date) {
                HabitDaySummarySheet(summary: summary,
                                     viewModel: habitsViewModel)
                .presentationDetents([.fraction(0.45), .medium])
            } else {
                Text("読み込み中...")
                    .padding()
            }
        }
        .sheet(isPresented: Binding<Bool>(
            get: { selectedHabitForDetail != nil },
            set: { if $0 == false { selectedHabitForDetail = nil } })
        ) {
            if let habit = selectedHabitForDetail {
                NavigationStack {
                    HabitDetailView(store: store, habit: habit)
                }
            }
        }
        .onChange(of: resetTrigger) {
            displayMode = .habits
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if displayMode == .habits {
                        showHabitReorder = true
                    } else {
                        showAnniversaryReorder = true
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(.primary)
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(isPresented: $showHabitReorder) {
            NavigationStack {
                HabitReorderView(habitsViewModel: habitsViewModel)
            }
        }
        .sheet(isPresented: $showAnniversaryReorder) {
            NavigationStack {
                AnniversaryReorderView(anniversaryViewModel: anniversaryViewModel)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
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
    }

    private var yearlyHeatmapSection: some View {
        Group {
            if monetization.canUseHabitGrass {
                SectionCard(title: "今年の習慣の積み上げ") {
                    if habitsViewModel.yearlySummaries.isEmpty {
                        Text("習慣がありません。追加して1年の積み上げを可視化しましょう。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HabitYearHeatmapView(startDate: habitsViewModel.yearStartDate,
                                             weekCount: habitsViewModel.yearWeekCount,
                                             summaries: habitsViewModel.yearlySummaries,
                                             onSelect: { summary in
                                                 selectedSummaryDate = summary.date
                                             })
                        VStack(alignment: .leading, spacing: 4) {
                            Text("今年の平均達成率： \(Int((habitsViewModel.yearlyAverageRate * 100).rounded()))%")
                            Text("今月の平均達成率： \(Int((habitsViewModel.monthlyAverageRate * 100).rounded()))%")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                }
            } else {
                PremiumLockCard(title: "今年の習慣の積み上げ",
                                message: monetization.habitGrassMessage(),
                                actionTitle: "プランを見る") {
                    showPaywall = true
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("表示切替", selection: $displayMode) {
            Text("習慣").tag(DisplayMode.habits)
            Text("カウントダウン").tag(DisplayMode.countdown)
            if !githubUsername.isEmpty {
                Text("GitHub").tag(DisplayMode.github)
            }
        }
        .pickerStyle(.segmented)
        .onAppear {
            if !githubUsername.isEmpty {
                _Concurrency.Task {
                    await githubService.fetchContributions(username: githubUsername)
                }
            }
        }
        .onChange(of: githubUsername) { _, newValue in
            if !newValue.isEmpty {
                _Concurrency.Task {
                    await githubService.fetchContributions(username: newValue)
                }
            }
        }
    }

    private var habitsSection: some View {
        let displayedStatuses = visibleHabitStatuses
        let hiddenCount = hiddenHabitCount
        return SectionCard(title: "習慣",
                           actionTitle: "追加",
                           action: { handleHabitAddTap() }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("行をタップすると詳細。長押しで順番を入れ替えれます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if displayedStatuses.isEmpty {
                    Text("まだ習慣がありません。追加して継続状況を可視化しましょう。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                } else {
                    ForEach(Array(displayedStatuses.enumerated()), id: \.element.id) { index, status in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                Button {
                                    selectedHabitForDetail = status.habit
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(hex: status.habit.colorHex) ?? .accentColor)
                                            .frame(width: 10, height: 10)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Label(status.habit.title, systemImage: status.habit.iconName)
                                            Text(scheduleDescription(for: status.habit.schedule))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            streakDisplay(for: status.habit)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                if monetization.canUseHabitGrass {
                                    MiniHabitHeatmapView(cells: habitsViewModel.miniHeatmap(for: status.habit),
                                                         accentColor: Color(hex: status.habit.colorHex) ?? .accentColor)
                                    .frame(width: 110, height: 82)
                                    .onTapGesture {
                                        selectedHabitForDetail = status.habit
                                    }
                                } else {
                                    Button {
                                        showPaywall = true
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: "lock.fill")
                                                .foregroundStyle(.yellow)
                                            Text("草表示")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 110, height: 82)
                                        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button {
                                    editingHabit = status.habit
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            weekRow(for: status)
                        }
                        .draggable(status.habit.id.uuidString) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: status.habit.colorHex) ?? .accentColor)
                                    .frame(width: 10, height: 10)
                                Text(status.habit.title)
                            }
                            .padding(8)
                            .background(.regularMaterial)
                            .cornerRadius(8)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedID = items.first,
                                  let draggedUUID = UUID(uuidString: draggedID),
                                  let fromIndex = habitsViewModel.statuses.firstIndex(where: { $0.habit.id == draggedUUID }),
                                  let toIndex = habitsViewModel.statuses.firstIndex(where: { $0.habit.id == status.habit.id }) else {
                                return false
                            }
                            if fromIndex != toIndex {
                                habitsViewModel.moveHabit(from: IndexSet(integer: fromIndex),
                                                          to: toIndex > fromIndex ? toIndex + 1 : toIndex)
                            }
                            return true
                        }
                        if index < displayedStatuses.count - 1 {
                            Divider()
                        }
                    }
                }
                if hiddenCount > 0 {
                    PremiumLockCard(title: "非表示の習慣があります",
                                    message: hiddenHabitMessage(hiddenCount),
                                    actionTitle: "プランを見る") {
                        showPaywall = true
                    }
                }
            }
        }
    }

    private var anniversarySection: some View {
        let displayedRows = visibleCountdownRows
        let hiddenCount = hiddenCountdownCount
        return SectionCard(title: "記念日 / カウントダウン",
                           actionTitle: "追加",
                           action: { handleCountdownAddTap() }) {
            Text("長押しで順番を入れ替えれます。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if displayedRows.isEmpty {
                Text("記念日は未登録です")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(displayedRows.enumerated()), id: \.element.id) { index, row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(row.anniversary.title)
                                .font(.headline)
                            Spacer()
                            // 開始日がない場合のみ従来の表示
                            if row.anniversary.startDate == nil {
                                Text(row.relativeText)
                                    .font(.headline)
                            }
                            Button {
                                editingAnniversary = row.anniversary
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        // 開始日がある場合は経過/残りを1行で左右に表示
                        if let elapsed = row.anniversary.elapsedDays(on: Date()),
                           let remaining = row.anniversary.remainingDays(on: Date()) {
                            HStack {
                                let startText = row.anniversary.startLabel ?? "開始から"
                                Text("\(startText) \(elapsed)日")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                let endText = row.anniversary.endLabel ?? "終了まで"
                                Text("\(endText) あと\(remaining)日")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            // 開始日がない場合は日付のみ
                            Text(row.anniversary.targetDate.jaYearMonthDayString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // プログレスバー（開始日が設定されている場合）
                        if let progress = row.anniversary.progress(on: Date()),
                           let totalDays = row.anniversary.totalDays {
                            VStack(spacing: 4) {
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(.systemGray5))
                                            .frame(height: 8)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.green)
                                            .frame(width: geometry.size.width * progress, height: 8)
                                    }
                                }
                                .frame(height: 8)
                                HStack {
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("全\(totalDays)日")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .draggable(row.anniversary.id.uuidString) {
                        Text(row.anniversary.title)
                            .padding(8)
                            .background(.regularMaterial)
                            .cornerRadius(8)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let draggedID = items.first,
                              let draggedUUID = UUID(uuidString: draggedID),
                              let fromIndex = anniversaryViewModel.rows.firstIndex(where: { $0.anniversary.id == draggedUUID }),
                              let toIndex = anniversaryViewModel.rows.firstIndex(where: { $0.anniversary.id == row.anniversary.id }) else {
                            return false
                        }
                        if fromIndex != toIndex {
                            anniversaryViewModel.move(from: IndexSet(integer: fromIndex),
                                                      to: toIndex > fromIndex ? toIndex + 1 : toIndex)
                        }
                        return true
                    }
                    if index < displayedRows.count - 1 {
                        Divider()
                    }
                }
            }
            if hiddenCount > 0 {
                PremiumLockCard(title: "非表示のカウントダウンがあります",
                                message: hiddenCountdownMessage(hiddenCount),
                                actionTitle: "プランを見る") {
                    showPaywall = true
                }
            }
        }
    }
}

extension HabitsCountdownView {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case habits = "習慣"
        case countdown = "カウントダウン"
        case github = "GitHub"

        var id: String { rawValue }
    }

    private func scheduleDescription(for schedule: HabitSchedule) -> String {
        switch schedule {
        case .daily:
            return "毎日"
        case .weekdays:
            return "平日"
        case .custom(let days):
            let labels = days.sorted { $0.rawValue < $1.rawValue }.map(\.shortLabel)
            return labels.joined(separator: " ")
        }
    }

    private func symbolName(for status: HabitsViewModel.HabitWeekStatus, on date: Date, isActive: Bool) -> String {
        if isActive == false {
            return "circle.fill"
        }
        return status.isCompleted(on: date) ? "checkmark.circle.fill" : "circle"
    }

    private func streakDisplay(for habit: Habit) -> some View {
        let current = habitsViewModel.currentStreak(for: habit)
        let best = habitsViewModel.maxStreak(for: habit)
        
        // ストリークに応じた絵文字とメッセージ
        let (emoji, message): (String, String?) = {
            if current > 365 {
                return ("🌟", "限界突破中！")
            } else if current == 365 {
                return ("🌟", "1年達成！")
            } else if current >= 200 {
                return ("🎖️", "レジェンド！")
            } else if current >= 100 {
                return ("👑", "100日突破！")
            } else if current >= 50 {
                return ("🏆", "すごい！")
            } else if current >= 30 {
                return ("🔥", "1ヶ月！")
            } else if current >= 21 {
                return ("🔥", "3週間！")
            } else if current >= 14 {
                return ("🔥", nil)
            } else if current >= 7 {
                return ("✨", nil)
            } else if current >= 3 {
                return ("💪", nil)
            } else if current == 0 && best > 0 {
                return ("📈", "最高\(best)日")
            } else {
                return ("", nil)
            }
        }()
        
        return HStack(spacing: 4) {
            if current > 0 {
                HStack(spacing: 2) {
                    Text(emoji)
                    Text("\(current)日連続")
                        .fontWeight(.medium)
                    if let message = message {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(current >= 7 ? Color.orange : .primary)
                
                if best > current {
                    Text("/ 最高\(best)日")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 2) {
                    Text(emoji)
                    if best > 0 {
                        Text("最高\(best)日達成済み")
                    } else {
                        Text("今日から始めよう")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var visibleHabitStatuses: [HabitsViewModel.HabitWeekStatus] {
        guard monetization.isPremiumUnlocked == false else { return habitsViewModel.statuses }
        return Array(habitsViewModel.statuses.prefix(monetization.freeHabitLimit))
    }

    private var hiddenHabitCount: Int {
        max(0, habitsViewModel.statuses.count - visibleHabitStatuses.count)
    }

    private var visibleCountdownRows: [AnniversaryViewModel.Row] {
        guard monetization.isPremiumUnlocked == false else { return anniversaryViewModel.rows }
        return Array(anniversaryViewModel.rows.prefix(monetization.freeCountdownLimit))
    }

    private var hiddenCountdownCount: Int {
        max(0, anniversaryViewModel.rows.count - visibleCountdownRows.count)
    }

    private func hiddenHabitMessage(_ hiddenCount: Int) -> String {
        "無料プランでは\(monetization.freeHabitLimit)件まで表示されます。\(hiddenCount)件は非表示です。プレミアムで再表示できます。"
    }

    private func hiddenCountdownMessage(_ hiddenCount: Int) -> String {
        "無料プランでは\(monetization.freeCountdownLimit)件まで表示されます。\(hiddenCount)件は非表示です。プレミアムで再表示できます。"
    }

    private func weekRow(for status: HabitsViewModel.HabitWeekStatus) -> some View {
        HStack(spacing: 6) {
            ForEach(habitsViewModel.weekDates, id: \.self) { date in
                let isToday = Calendar.current.isDateInToday(date)
                VStack(spacing: 4) {
                    Text(date, format: .dateTime.weekday(.narrow))
                        .font(.caption2.weight(isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? .primary : .secondary)
                        .frame(width: 22, height: 22)
                        .background {
                            if isToday {
                                Circle()
                                    .fill(Color.secondary.opacity(0.2))
                            }
                        }
                    Button {
                        habitsViewModel.toggle(habit: status.habit, on: date)
                    } label: {
                        let isActive = status.isActive(on: date)
                        if isActive {
                            AnimatedCheckmark(
                                isCompleted: status.isCompleted(on: date),
                                color: Color(hex: status.habit.colorHex) ?? .accentColor,
                                size: 24
                            )
                        } else {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(Color.black)
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(status.isActive(on: date) == false)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func handleHabitAddTap() {
        guard monetization.canAddHabit(activeHabitCount: habitsViewModel.habits.count) else {
            premiumAlertMessage = monetization.habitLimitMessage()
            return
        }
        showHabitEditor = true
    }

    private func handleCountdownAddTap() {
        guard monetization.canAddCountdown(currentCount: anniversaryViewModel.rows.count) else {
            premiumAlertMessage = monetization.countdownLimitMessage()
            return
        }
        showAnniversaryEditor = true
    }
}

struct MiniHabitHeatmapView: View {
    let cells: [HabitHeatCell]
    let accentColor: Color

    var body: some View {
        let weeks = chunkedWeeks()

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                        VStack(spacing: 4) {
                            ForEach(week) { cell in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color(for: cell.state))
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(cell.isToday ? Color.white.opacity(0.95) : .clear, lineWidth: 1)
                                    )
                                    .scaleEffect(cell.isToday ? 1.05 : 1.0)
                            }
                        }
                        .id(index)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                if let last = weeks.indices.last {
                    proxy.scrollTo(last, anchor: .trailing)
                }
            }
        }
        .frame(height: 82)
    }

    private func color(for state: HabitHeatCell.State) -> Color {
        switch state {
        case .inactive:
            return Color.gray.opacity(0.2)
        case .pending:
            return Color.secondary.opacity(0.45)
        case .completed:
            return accentColor
        }
    }

    private func chunkedWeeks() -> [[HabitHeatCell]] {
        guard cells.isEmpty == false else { return [] }
        let sorted = cells.sorted { $0.date < $1.date }
        var weeks: [[HabitHeatCell]] = []
        var index = 0
        while index < sorted.count {
            let end = min(index + 7, sorted.count)
            let slice = Array(sorted[index..<end])
            if slice.count == 7 {
                weeks.append(slice)
            }
            index += 7
        }
        return weeks
    }
}

struct HabitYearHeatmapView: View {
    let startDate: Date
    let weekCount: Int
    let summaries: [Date: HabitDaySummary]
    let onSelect: (HabitDaySummary) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let calendar = Calendar.current

    var body: some View {
        let thresholds = completionThresholds

        VStack(alignment: .trailing, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 4) {
                        ForEach(0..<weekCount, id: \.self) { week in
                            VStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { offset in
                                    let index = week * 7 + offset
                                    let date = calendar.date(byAdding: .day, value: index, to: startDate) ?? startDate
                                    let day = calendar.startOfDay(for: date)
                                    let summary = summaries[day]
                                    let isToday = calendar.isDate(day, inSameDayAs: Date())
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(color(for: summary, thresholds: thresholds))
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(isToday ? Color.white.opacity(0.9) : Color.black.opacity(0.08), lineWidth: isToday ? 1.6 : 1)
                                        )
                                        .scaleEffect(isToday ? 1.15 : 1.0)
                                        .onTapGesture {
                                            if let summary {
                                                onSelect(summary)
                                            }
                                        }
                                }
                            }
                            .id(week)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .onAppear {
                    // 最新週（右端）にスクロール
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(weekCount - 1, anchor: .trailing)
                    }
                }
            }

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text("少")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(githubPalette[level])
                        .frame(width: 10, height: 10)
                }
                Text("多")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private typealias Thresholds = (q1: Int, q2: Int, q3: Int)

    private func color(for summary: HabitDaySummary?, thresholds: Thresholds) -> Color {
        githubPalette[level(for: summary, thresholds: thresholds)]
    }

    private func level(for summary: HabitDaySummary?, thresholds: Thresholds) -> Int {
        guard let summary, summary.scheduledCount > 0 else { return 0 }
        let value = summary.completedCount
        guard value > 0 else { return 0 }

        if value <= thresholds.q1 { return 1 }
        if value <= thresholds.q2 { return 2 }
        if value <= thresholds.q3 { return 3 }
        return 4
    }

    private var completionThresholds: Thresholds {
        let values = nonZeroCompletionCounts
        return (
            q1: nearestRankPercentile(25, in: values),
            q2: nearestRankPercentile(50, in: values),
            q3: nearestRankPercentile(75, in: values)
        )
    }

    private var nonZeroCompletionCounts: [Int] {
        var counts: [Int] = []
        counts.reserveCapacity(weekCount * 7)

        for index in 0..<(weekCount * 7) {
            let date = calendar.date(byAdding: .day, value: index, to: startDate) ?? startDate
            let day = calendar.startOfDay(for: date)
            guard let summary = summaries[day], summary.scheduledCount > 0 else { continue }
            if summary.completedCount > 0 {
                counts.append(summary.completedCount)
            }
        }

        return counts.sorted()
    }

    private func nearestRankPercentile(_ percentile: Int, in sortedValues: [Int]) -> Int {
        guard sortedValues.isEmpty == false else { return 1 }
        let p = Double(percentile) / 100.0
        let rank = max(1, Int(ceil(Double(sortedValues.count) * p)))
        return sortedValues[min(rank - 1, sortedValues.count - 1)]
    }

    private var githubPalette: [Color] {
        if colorScheme == .dark {
            return [
                Color(hex: "#161b22") ?? Color(red: 0.09, green: 0.11, blue: 0.13),
                Color(hex: "#0e4429") ?? Color(red: 0.05, green: 0.27, blue: 0.16),
                Color(hex: "#006d32") ?? Color(red: 0.00, green: 0.43, blue: 0.20),
                Color(hex: "#26a641") ?? Color(red: 0.15, green: 0.65, blue: 0.25),
                Color(hex: "#39d353") ?? Color(red: 0.22, green: 0.83, blue: 0.33)
            ]
        }

        return [
            Color(hex: "#ebedf0") ?? Color(red: 0.92, green: 0.93, blue: 0.94),
            Color(hex: "#9be9a8") ?? Color(red: 0.61, green: 0.91, blue: 0.66),
            Color(hex: "#40c463") ?? Color(red: 0.25, green: 0.77, blue: 0.39),
            Color(hex: "#30a14e") ?? Color(red: 0.19, green: 0.63, blue: 0.31),
            Color(hex: "#216e39") ?? Color(red: 0.13, green: 0.43, blue: 0.22)
        ]
    }
}

struct HabitDaySummarySheet: View {
    let summary: HabitDaySummary
    @ObservedObject var viewModel: HabitsViewModel
    private let calendar = Calendar.current

    var body: some View {
        let currentSummary = viewModel.summary(for: summary.date) ?? summary
        let rate = currentSummary.scheduledCount > 0 ? Double(currentSummary.completedCount) / Double(currentSummary.scheduledCount) : 0
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(currentSummary.date, formatter: DateFormatter.japaneseYearMonthDay)
                    .font(.headline)
                Text("\(currentSummary.completedCount) / \(currentSummary.scheduledCount) 個の習慣を達成 (\(Int(rate * 100))%)")
                    .font(.subheadline)
            }
            if currentSummary.scheduledCount == 0 {
                Text("この日は予定された習慣はありません。")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(currentSummary.scheduledHabits, id: \.id) { habit in
                        let isDone = currentSummary.completedHabits.contains { $0.id == habit.id }
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: habit.colorHex) ?? .accentColor)
                                    .frame(width: 10, height: 10)
                                Text(habit.title)
                            }
                            Spacer()
                            Button {
                                viewModel.setHabit(habit, on: currentSummary.date, completed: !isDone)
                            } label: {
                                AnimatedCheckmark(
                                    isCompleted: isDone,
                                    color: Color(hex: habit.colorHex) ?? .accentColor,
                                    size: 24
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding()
        .toast()
    }
}

// MARK: - 習慣並び替えビュー
private struct HabitReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var habitsViewModel: HabitsViewModel
    
    var body: some View {
        List {
            ForEach(habitsViewModel.habits) { habit in
                HStack {
                    Circle()
                        .fill(Color(hex: habit.colorHex) ?? .accentColor)
                        .frame(width: 10, height: 10)
                    Text(habit.title)
                }
            }
            .onMove { source, destination in
                habitsViewModel.moveHabit(from: source, to: destination)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("習慣の並び替え")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") { dismiss() }
            }
        }
    }
}

// MARK: - カウントダウン並び替えビュー
private struct AnniversaryReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var anniversaryViewModel: AnniversaryViewModel
    
    var body: some View {
        List {
            ForEach(anniversaryViewModel.rows) { row in
                Text(row.anniversary.title)
            }
            .onMove { source, destination in
                anniversaryViewModel.move(from: source, to: destination)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("カウントダウンの並び替え")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") { dismiss() }
            }
        }
    }
}
