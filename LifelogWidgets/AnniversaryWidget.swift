//
//  AnniversaryWidget.swift
//  LifelogWidgets
//
//  Rebuilt for configurable countdown widgets
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

private struct AnniversaryWidgetModel {
    let id: UUID
    let title: String
    let targetDate: Date
    let type: AnniversaryType
    let repeatsYearly: Bool
    let startDate: Date?
}

private enum AnniversaryWidgetStore {
    @MainActor
    static func fetchAll() -> [AnniversaryWidgetModel] {
        do {
            let context = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<SDAnniversary>(sortBy: [SortDescriptor(\.orderIndex)])
            return try context.fetch(descriptor).map {
                AnniversaryWidgetModel(
                    id: $0.id,
                    title: $0.title,
                    targetDate: $0.targetDate,
                    type: $0.type,
                    repeatsYearly: $0.repeatsYearly,
                    startDate: $0.startDate
                )
            }
        } catch {
            return []
        }
    }

    @MainActor
    static func fetchByID(_ id: UUID) -> AnniversaryWidgetModel? {
        do {
            let context = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<SDAnniversary>(predicate: #Predicate { $0.id == id })
            return try context.fetch(descriptor).first.map {
                AnniversaryWidgetModel(
                    id: $0.id,
                    title: $0.title,
                    targetDate: $0.targetDate,
                    type: $0.type,
                    repeatsYearly: $0.repeatsYearly,
                    startDate: $0.startDate
                )
            }
        } catch {
            return nil
        }
    }
}

struct AnniversaryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "記念日")
    static var defaultQuery = AnniversaryEntityQuery()

    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    fileprivate init(model: AnniversaryWidgetModel) {
        self.id = model.id.uuidString
        self.title = model.title
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct AnniversaryEntityQuery: EntityQuery {
    func entities(for identifiers: [AnniversaryEntity.ID]) async throws -> [AnniversaryEntity] {
        await MainActor.run {
            let targets = Set(identifiers)
            return AnniversaryWidgetStore.fetchAll()
                .map(AnniversaryEntity.init(model:))
                .filter { targets.contains($0.id) }
        }
    }

    func suggestedEntities() async throws -> [AnniversaryEntity] {
        await MainActor.run {
            AnniversaryWidgetStore.fetchAll().map(AnniversaryEntity.init(model:))
        }
    }

    func defaultResult() async -> AnniversaryEntity? {
        try? await suggestedEntities().first
    }
}

struct AnniversarySelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "記念日を選択"
    static var description = IntentDescription("長押しして「ウィジェットを編集」から表示する記念日を変更できます。")

    @Parameter(title: "記念日")
    var anniversary: AnniversaryEntity?

    init() {}
}

private struct AnniversaryEntry: TimelineEntry {
    let date: Date
    let anniversary: AnniversaryWidgetModel?
}

private struct AnniversaryPresentation {
    let title: String
    let valueText: String
    let subtitleText: String
    let anchorDateText: String
    let progress: Double?
    let progressText: String?
    let rangeText: String?
    let accentColor: Color
}

private enum AnniversaryCalculation {
    static let calendar = Calendar.current

    static func presentation(for model: AnniversaryWidgetModel, now: Date) -> AnniversaryPresentation {
        let today = calendar.startOfDay(for: now)
        let effectiveTarget = resolvedTargetDate(for: model, today: today)

        let valueText: String
        let subtitleText: String
        let anchorText: String
        let accent: Color

        switch model.type {
        case .countdown:
            let days = max(0, dayDiff(from: today, to: effectiveTarget))
            valueText = "D-\(days)"
            subtitleText = days == 0 ? "今日です" : "あと\(days)日"
            anchorText = "終了: \(AnniversaryFormatter.fullDate.string(from: effectiveTarget))"
            accent = .blue

        case .since:
            let startPoint = resolvedSinceBaseDate(for: model, today: today)
            let days = max(0, dayDiff(from: startPoint, to: today))
            valueText = "+\(days)"
            subtitleText = "\(days)日経過"
            anchorText = "起点: \(AnniversaryFormatter.fullDate.string(from: startPoint))"
            accent = .orange
        }

        var progress: Double?
        var progressText: String?
        var rangeText: String?
        if let configuredStart = model.startDate {
            let startPoint = resolvedProgressStartDate(configuredStart, model: model, effectiveTarget: effectiveTarget)
            if let rate = progressRate(start: startPoint, end: effectiveTarget, now: today) {
                progress = rate
                progressText = "\(Int(rate * 100))%"
                rangeText = "\(AnniversaryFormatter.shortDate.string(from: startPoint)) - \(AnniversaryFormatter.shortDate.string(from: effectiveTarget))"
            }
        }

        return AnniversaryPresentation(
            title: model.title,
            valueText: valueText,
            subtitleText: subtitleText,
            anchorDateText: anchorText,
            progress: progress,
            progressText: progressText,
            rangeText: rangeText,
            accentColor: accent
        )
    }

    private static func resolvedTargetDate(for model: AnniversaryWidgetModel, today: Date) -> Date {
        guard model.repeatsYearly else { return model.targetDate }
        return nextOccurrence(of: model.targetDate, from: today)
    }

    private static func resolvedSinceBaseDate(for model: AnniversaryWidgetModel, today: Date) -> Date {
        guard model.repeatsYearly else { return model.targetDate }
        return mostRecentOccurrence(of: model.targetDate, onOrBefore: today)
    }

    private static func resolvedProgressStartDate(
        _ configuredStart: Date,
        model: AnniversaryWidgetModel,
        effectiveTarget: Date
    ) -> Date {
        guard model.repeatsYearly else { return configuredStart }
        var start = mostRecentOccurrence(of: configuredStart, onOrBefore: effectiveTarget)
        if start > effectiveTarget {
            start = calendar.date(byAdding: .year, value: -1, to: start) ?? start
        }
        return start
    }

    private static func progressRate(start: Date, end: Date, now: Date) -> Double? {
        let total = dayDiff(from: start, to: end)
        guard total > 0 else { return nil }
        let elapsed = dayDiff(from: start, to: now)
        let raw = Double(elapsed) / Double(total)
        return min(max(raw, 0), 1)
    }

    private static func dayDiff(from: Date, to: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    private static func nextOccurrence(of baseDate: Date, from reference: Date) -> Date {
        let components = calendar.dateComponents([.month, .day], from: baseDate)
        let searchFrom = calendar.date(byAdding: .second, value: -1, to: reference) ?? reference
        return calendar.nextDate(
            after: searchFrom,
            matching: components,
            matchingPolicy: .nextTimePreservingSmallerComponents
        ) ?? baseDate
    }

    private static func mostRecentOccurrence(of baseDate: Date, onOrBefore reference: Date) -> Date {
        let components = calendar.dateComponents([.month, .day], from: baseDate)
        let referenceYear = calendar.component(.year, from: reference)
        let thisYear = calendar.date(from: DateComponents(year: referenceYear, month: components.month, day: components.day))
        if let thisYear, thisYear <= reference {
            return thisYear
        }
        if let thisYear {
            return calendar.date(byAdding: .year, value: -1, to: thisYear) ?? baseDate
        }
        return baseDate
    }
}

private enum AnniversaryFormatter {
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        return formatter
    }()
}

private struct AnniversaryProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 8)
    }
}

private struct AnniversaryWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AnniversaryEntry

    var body: some View {
        if let model = entry.anniversary {
            let presentation = AnniversaryCalculation.presentation(for: model, now: entry.date)
            switch family {
            case .systemSmall:
                smallLayout(presentation)
            case .systemMedium:
                mediumLayout(presentation)
            default:
                largeLayout(presentation)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("表示できる記念日がありません")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
    }

    private func valueText(_ text: String, size: CGFloat, minScale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(minScale)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func smallLayout(_ p: AnniversaryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(p.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Spacer(minLength: 0)

            valueText(p.valueText, size: 32, minScale: 0.62)

            Text(p.subtitleText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let progress = p.progress {
                AnniversaryProgressBar(value: progress, color: p.accentColor)
            }

            Text(p.anchorDateText)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
    }

    private func mediumLayout(_ p: AnniversaryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(p.subtitleText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(p.valueText)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }

            if let progress = p.progress {
                AnniversaryProgressBar(value: progress, color: p.accentColor)
                HStack {
                    Text(p.rangeText ?? p.anchorDateText)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(p.progressText ?? "")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(p.anchorDateText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
    }

    private func largeLayout(_ p: AnniversaryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(p.title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                valueText(p.valueText, size: 44, minScale: 0.6)
                    .layoutPriority(1)
                Text(p.subtitleText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if let progress = p.progress {
                AnniversaryProgressBar(value: progress, color: p.accentColor)
                    .frame(height: 10)
                HStack {
                    Text(p.rangeText ?? p.anchorDateText)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(p.progressText ?? "")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(p.anchorDateText)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

private struct AnniversaryProvider: AppIntentTimelineProvider {
    typealias Entry = AnniversaryEntry
    typealias Intent = AnniversarySelectionIntent

    func placeholder(in context: Context) -> AnniversaryEntry {
        AnniversaryEntry(
            date: Date(),
            anniversary: AnniversaryWidgetModel(
                id: UUID(),
                title: "誕生日",
                targetDate: Date().addingTimeInterval(60 * 60 * 24 * 10),
                type: .countdown,
                repeatsYearly: true,
                startDate: Date().addingTimeInterval(-60 * 60 * 24 * 20)
            )
        )
    }

    func snapshot(for configuration: AnniversarySelectionIntent, in context: Context) async -> AnniversaryEntry {
        let selected = await resolveAnniversary(for: configuration)
        return AnniversaryEntry(date: Date(), anniversary: selected)
    }

    func timeline(for configuration: AnniversarySelectionIntent, in context: Context) async -> Timeline<AnniversaryEntry> {
        let now = Date()
        let selected = await resolveAnniversary(for: configuration)
        let entry = AnniversaryEntry(date: now, anniversary: selected)
        let next = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func resolveAnniversary(for configuration: AnniversarySelectionIntent) async -> AnniversaryWidgetModel? {
        await MainActor.run {
            if let entity = configuration.anniversary,
               let id = UUID(uuidString: entity.id),
               let selected = AnniversaryWidgetStore.fetchByID(id) {
                return selected
            }
            return AnniversaryWidgetStore.fetchAll().first
        }
    }
}

struct AnniversaryWidget: Widget {
    let kind: String = "AnniversaryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: AnniversarySelectionIntent.self, provider: AnniversaryProvider()) { entry in
            if #available(iOS 17.0, *) {
                AnniversaryWidgetEntryView(entry: entry)
                    .containerBackground(Color(uiColor: .systemBackground), for: .widget)
            } else {
                AnniversaryWidgetEntryView(entry: entry)
                    .background(Color(uiColor: .systemBackground))
            }
        }
        .configurationDisplayName("記念日 / カウントダウン")
        .description("記念日の日数と進捗を表示します。追加後は長押しで編集できます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
