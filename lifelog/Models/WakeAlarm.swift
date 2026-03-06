//
//  WakeAlarm.swift
//  lifelog
//
//  AlarmKit-backed wake alarms with anti-snooze challenges.
//

import Foundation

enum WakeChallengeMethod: String, Codable, CaseIterable, Identifiable, Hashable {
    case mentalMath
    case shortTermMemory
    case randomString
    case shake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mentalMath:
            return "暗算"
        case .shortTermMemory:
            return "短期記憶"
        case .randomString:
            return "文字列入力"
        case .shake:
            return "シェイク"
        }
    }

    var detail: String {
        switch self {
        case .mentalMath:
            return "3問連続で正解"
        case .shortTermMemory:
            return "表示された数字を記憶"
        case .randomString:
            return "ランダムな文字列を正確に入力"
        case .shake:
            return "端末を複数回振る"
        }
    }

    var iconName: String {
        switch self {
        case .mentalMath:
            return "plus.forwardslash.minus"
        case .shortTermMemory:
            return "brain"
        case .randomString:
            return "textformat.abc"
        case .shake:
            return "iphone.radiowaves.left.and.right"
        }
    }
}

struct WakeAlarm: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var hour: Int
    var minute: Int
    var repeatDays: [Weekday]
    var challengeMethod: WakeChallengeMethod
    var isEnabled: Bool
    var createdAt: Date
    var lastChallengeSuccessAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        hour: Int,
        minute: Int,
        repeatDays: [Weekday] = Weekday.allCases,
        challengeMethod: WakeChallengeMethod = .mentalMath,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        lastChallengeSuccessAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.hour = hour
        self.minute = minute
        self.repeatDays = Self.normalizedRepeatDays(repeatDays)
        self.challengeMethod = challengeMethod
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastChallengeSuccessAt = lastChallengeSuccessAt
    }

    static func normalizedRepeatDays(_ days: [Weekday]) -> [Weekday] {
        var seen: Set<Weekday> = []
        return days
            .sorted { $0.rawValue < $1.rawValue }
            .filter { seen.insert($0).inserted }
    }

    var repeatsWeekly: Bool {
        repeatDays.isEmpty == false
    }

    var isEveryDay: Bool {
        Set(repeatDays) == Set(Weekday.allCases)
    }

    var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeStyle = .short

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    var repeatSummary: String {
        if repeatDays.isEmpty {
            return "次回1回"
        }
        if isEveryDay {
            return "毎日"
        }
        return repeatDays.map(\.shortLabel).joined(separator: " ")
    }
}

