//
//  CalendarDetailPanel.swift
//  lifelog
//

import SwiftUI
import UIKit

struct TimelineItemDetailView: View {
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

    private var presentationHeight: CGFloat {
        if item.kind == .event,
           let eventDetail = item.eventDetail,
           eventDetail.isEmpty == false {
            return 220
        }
        return 180
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

                if item.kind == .event,
                   let eventDetail = item.eventDetail,
                   eventDetail.isEmpty == false {
                    Label(eventDetail, systemImage: "note.text")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
        .presentationDetents([.height(presentationHeight)])
    }
}

struct CalendarDetailSnapshot {
    let date: Date
    let events: [CalendarEvent]
    let pendingTasks: [Task]
    let completedTasks: [Task]
    let habitStatuses: [TodayViewModel.DailyHabitStatus]
    let healthSummary: HealthSummary?
    let diaryEntry: DiaryEntry?
}

struct CalendarDetailPanel: View {
    let snapshot: CalendarDetailSnapshot
    let store: AppDataStore
    let isDiaryTextHidden: Bool
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
                                        Label(eventTimeLabel(for: event), systemImage: "clock")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if event.detail.isEmpty == false {
                                            Text(event.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
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
                                if isDiaryTextHidden {
                                    Text("日記本文は非表示です。")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(entry.text)
                                        .font(.body)
                                }
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
                            if isDiaryTextHidden {
                                placeholder("日記本文は非表示です。")
                            } else {
                                placeholder("まだ日記は追加されていません")
                            }
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

struct SummaryChip: View {
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

struct OverviewSection<Content: View>: View {
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

struct DetailPagerHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TimelineColumnView: View {
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

                                if item.kind == .event,
                                   let eventDetail = item.eventDetail,
                                   eventDetail.isEmpty == false,
                                   blockHeight >= threshold {
                                    Text(eventDetail)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

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

struct DetailPanelPhotoPage: View {
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
