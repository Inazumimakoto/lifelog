//
//  MemoWidget.swift
//  LifelogWidgets
//
//  Created for Widget Implementation
//

import WidgetKit
import SwiftUI
import SwiftData

private enum MemoWidgetPrivacy {
    private static let hiddenKey = "isMemoTextHidden"
    private static let authKey = "requiresMemoOpenAuthentication"

    static func current() -> (isHidden: Bool, requiresOpenAuth: Bool) {
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
        return (
            isHidden: defaults.bool(forKey: hiddenKey),
            requiresOpenAuth: defaults.bool(forKey: authKey)
        )
    }
}

private struct MemoWidgetData {
    let text: String
    let updatedAt: Date?
    let isHidden: Bool
    let requiresOpenAuth: Bool
}

struct MemoProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemoEntry {
        MemoEntry(
            date: Date(),
            text: "買い物メモ\n・牛乳\n・キッチンペーパー",
            updatedAt: Date(),
            isHidden: false,
            requiresOpenAuth: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoEntry) -> ()) {
        _Concurrency.Task { @MainActor in
            let entry = loadEntry(at: Date())
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoEntry>) -> ()) {
        _Concurrency.Task { @MainActor in
            let entry = loadEntry(at: Date())
            
            // Refresh every 15 mins or on app open (OS managed)
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }

    @MainActor
    private func loadEntry(at date: Date) -> MemoEntry {
        let memo = fetchMemo()
        return MemoEntry(
            date: date,
            text: memo.text,
            updatedAt: memo.updatedAt,
            isHidden: memo.isHidden,
            requiresOpenAuth: memo.requiresOpenAuth
        )
    }

    @MainActor
    private func fetchMemo() -> MemoWidgetData {
        let privacy = MemoWidgetPrivacy.current()
        do {
            let descriptor = FetchDescriptor<SDMemoPad>()
            // Use the shared container which has the proper full schema
            let memos = try PersistenceController.shared.container.mainContext.fetch(descriptor)
            guard let memo = memos.first else {
                return MemoWidgetData(
                    text: "",
                    updatedAt: nil,
                    isHidden: privacy.isHidden,
                    requiresOpenAuth: privacy.requiresOpenAuth
                )
            }
            return MemoWidgetData(
                text: memo.text,
                updatedAt: memo.lastUpdatedAt,
                isHidden: privacy.isHidden,
                requiresOpenAuth: privacy.requiresOpenAuth
            )
        } catch {
            return MemoWidgetData(
                text: "読み込みエラー",
                updatedAt: nil,
                isHidden: privacy.isHidden,
                requiresOpenAuth: privacy.requiresOpenAuth
            )
        }
    }
}

struct MemoEntry: TimelineEntry {
    let date: Date
    let text: String
    let updatedAt: Date?
    let isHidden: Bool
    let requiresOpenAuth: Bool
}

private enum MemoWidgetFormatter {
    static let updatedAt: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
}

struct MemoWidgetEntryView : View {
    @Environment(\.widgetFamily) private var family
    var entry: MemoProvider.Entry

    private var normalizedText: String {
        if entry.isHidden {
            return "メモ本文は非表示です。"
        }
        let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "メモはありません"
        }
        return trimmed
    }

    private var bodyFont: Font {
        switch family {
        case .systemSmall:
            return .system(size: 11.5, weight: .medium, design: .rounded)
        case .systemMedium:
            return .system(size: 11.5, weight: .medium, design: .rounded)
        default:
            return .system(size: 11.5, weight: .medium, design: .rounded)
        }
    }

    private var horizontalPadding: CGFloat {
        switch family {
        case .systemSmall: return 7
        case .systemMedium: return 8
        default: return 8
        }
    }

    private var verticalPadding: CGFloat {
        switch family {
        case .systemSmall: return 5
        case .systemMedium: return 5
        default: return 6
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            header

            if family == .systemMedium {
                mediumTwoColumnText
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                memoText(normalizedText, lineLimit: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if entry.isHidden && entry.requiresOpenAuth {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("タップ後に認証して開く")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    private var mediumTwoColumnText: some View {
        let columns = splitIntoTwoColumnsPreservingContent(normalizedText)

        return HStack(alignment: .top, spacing: 8) {
            memoText(columns.left, lineLimit: nil)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            memoText(columns.right, lineLimit: nil)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func memoText(_ text: String, lineLimit: Int?) -> some View {
        Text(text)
            .font(bodyFont)
            .foregroundStyle(
                normalizedText == "メモはありません" || entry.isHidden ? .secondary : .primary
            )
            .lineLimit(lineLimit)
            .lineSpacing(0.5)
            .multilineTextAlignment(.leading)
    }

    private func splitIntoTwoColumnsPreservingContent(_ text: String) -> (left: String, right: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else {
            return splitSingleLineForMedium(text)
        }

        var leftLines: [String] = []
        var rightLines: [String] = []
        var leftWeight = 0
        var rightWeight = 0

        for line in lines {
            let weight = estimatedLineWeight(line)
            if leftWeight <= rightWeight {
                leftLines.append(line)
                leftWeight += weight
            } else {
                rightLines.append(line)
                rightWeight += weight
            }
        }

        if rightLines.isEmpty {
            return splitSingleLineForMedium(text)
        }

        return (
            left: leftLines.joined(separator: "\n"),
            right: rightLines.joined(separator: "\n")
        )
    }

    private func estimatedLineWeight(_ line: String) -> Int {
        let visible = line.trimmingCharacters(in: .whitespaces)
        guard visible.isEmpty == false else { return 1 }
        let approxCharactersPerRow = 11
        return max(1, Int(ceil(Double(visible.count) / Double(approxCharactersPerRow))))
    }

    private func splitSingleLineForMedium(_ text: String) -> (left: String, right: String) {
        let chars = Array(text)
        guard chars.count > 1 else {
            return (left: text, right: "")
        }

        let midpoint = chars.count / 2
        let window = 20
        let lower = max(1, midpoint - window)
        let upper = min(chars.count - 1, midpoint + window)
        let boundaryCharacters = CharacterSet(charactersIn: " 、。,.!?:;/-")

        if let boundary = (lower...upper).first(where: { index in
            let scalar = String(chars[index]).unicodeScalars.first
            guard let scalar else { return false }
            return boundaryCharacters.contains(scalar)
        }) {
            return (
                left: String(chars[0..<boundary]),
                right: String(chars[boundary..<chars.count])
            )
        }

        return (
            left: String(chars[0..<midpoint]),
            right: String(chars[midpoint..<chars.count])
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 3) {
            Image(systemName: "note.text")
                .font(.system(size: family == .systemSmall ? 10 : 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("メモ")
                .font(.system(size: family == .systemSmall ? 10 : 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if family != .systemSmall, let updatedAt = entry.updatedAt {
                Text(MemoWidgetFormatter.updatedAt.string(from: updatedAt))
                    .font(.system(size: 8.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

struct MemoWidget: Widget {
    let kind: String = "MemoWidget"
    private let destinationURL = URL(string: "lifelog://memo")!

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemoProvider()) { entry in
            if #available(iOS 17.0, *) {
                MemoWidgetEntryView(entry: entry)
                    .containerBackground(Color(uiColor: .systemBackground), for: .widget)
                    .widgetURL(destinationURL)
            } else {
                MemoWidgetEntryView(entry: entry)
                    .background(Color(uiColor: .systemBackground))
                    .widgetURL(destinationURL)
            }
        }
        .configurationDisplayName("メモ")
        .description("メモ内容を表示します。タップでメモ編集を開けます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
