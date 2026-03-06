//
//  WakeAlarmService.swift
//  lifelog
//

import Foundation
import SwiftUI
#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
#endif

enum WakeAlarmAuthorizationStatus: Equatable {
    case unsupported
    case notDetermined
    case denied
    case authorized
}

enum WakeAlarmServiceError: LocalizedError {
    case unsupportedOS
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "目覚まし機能は iOS 26 以降で利用できます。"
        case .unauthorized:
            return "目覚ましの許可が必要です。"
        }
    }
}

final class WakeAlarmService {
    static let shared = WakeAlarmService()

    private init() {}

    var isSupported: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    func authorizationStatus() async -> WakeAlarmAuthorizationStatus {
        guard #available(iOS 26.0, *) else {
            return .unsupported
        }

        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func requestAuthorization() async -> WakeAlarmAuthorizationStatus {
        guard #available(iOS 26.0, *) else {
            return .unsupported
        }

        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            switch state {
            case .authorized:
                return .authorized
            case .denied:
                return .denied
            case .notDetermined:
                return .notDetermined
            @unknown default:
                return .notDetermined
            }
        } catch {
            return .denied
        }
    }

    func schedule(_ alarm: WakeAlarm) async throws {
        guard #available(iOS 26.0, *) else {
            throw WakeAlarmServiceError.unsupportedOS
        }

        try? AlarmManager.shared.cancel(id: alarm.id)
        guard alarm.isEnabled else { return }

        let authorization = await authorizationStatus()
        guard authorization == .authorized else {
            throw WakeAlarmServiceError.unauthorized
        }

        let stopIntent = WakeAlarmChallengeIntent(alarmID: alarm.id.uuidString)

        let alert = alertPresentation()
        let presentation = AlarmPresentation(alert: alert)
        let metadata = WakeAlarmMetadata(
            alarmID: alarm.id,
            title: alarm.title,
            challengeMethod: alarm.challengeMethod
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: .orange
        )

        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule(for: alarm),
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: nil,
            sound: .default
        )

        _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: configuration)
    }

    func cancel(alarmID: UUID) throws {
        guard #available(iOS 26.0, *) else {
            throw WakeAlarmServiceError.unsupportedOS
        }
        try AlarmManager.shared.cancel(id: alarmID)
    }

    func stop(alarmID: UUID) throws {
        guard #available(iOS 26.0, *) else {
            throw WakeAlarmServiceError.unsupportedOS
        }
        try AlarmManager.shared.stop(id: alarmID)
    }

    @available(iOS 26.0, *)
    private func schedule(for alarm: WakeAlarm) -> Alarm.Schedule {
        if alarm.repeatDays.isEmpty {
            return .fixed(nextFixedDate(for: alarm))
        }

        let weekdayValues = alarm.repeatDays.map(\.localeWeekday)
        let time = Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        return .relative(.init(time: time, repeats: .weekly(weekdayValues)))
    }

    @available(iOS 26.0, *)
    private func nextFixedDate(for alarm: WakeAlarm) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = alarm.hour
        components.minute = alarm.minute
        components.second = 0

        let today = calendar.date(from: components) ?? now
        if today > now {
            return today
        }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }

    @available(iOS 26.0, *)
    private func alertPresentation() -> AlarmPresentation.Alert {
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: "解除テストを開始")
        }

        let stopButton = AlarmButton(
            text: "解除テスト",
            textColor: .white,
            systemImageName: "checkmark.circle.fill"
        )
        return AlarmPresentation.Alert(title: "解除テストを開始", stopButton: stopButton)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct WakeAlarmMetadata: AlarmMetadata {
    let alarmID: UUID
    let title: String
    let challengeMethod: WakeChallengeMethod
}

@available(iOS 26.0, *)
private extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday:
            return .sunday
        case .monday:
            return .monday
        case .tuesday:
            return .tuesday
        case .wednesday:
            return .wednesday
        case .thursday:
            return .thursday
        case .friday:
            return .friday
        case .saturday:
            return .saturday
        }
    }
}
#endif
