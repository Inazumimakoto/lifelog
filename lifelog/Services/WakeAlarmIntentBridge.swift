//
//  WakeAlarmIntentBridge.swift
//  lifelog
//

import Foundation

enum WakeAlarmIntentBridge {
    private static let pendingWakeChallengeAlarmIDKey = "wakeAlarm.pendingChallengeAlarmID"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
    }

    static func markPendingWakeChallenge(alarmID: UUID) {
        defaults.set(alarmID.uuidString, forKey: pendingWakeChallengeAlarmIDKey)
    }

    static func pendingWakeChallengeAlarmID() -> UUID? {
        guard let raw = defaults.string(forKey: pendingWakeChallengeAlarmIDKey) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    static func clearPendingWakeChallenge() {
        defaults.removeObject(forKey: pendingWakeChallengeAlarmIDKey)
    }
}
