//
//  WakeAlarmChallengeIntent.swift
//  lifelog
//

import AppIntents
import Foundation

struct WakeAlarmChallengeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "解除テストを開く"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        .foreground(.dynamic)
    }

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {
        self.alarmID = ""
    }

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        if let alarmUUID = UUID(uuidString: alarmID) {
            await WakeAlarmIntentBridge.markPendingWakeChallenge(alarmID: alarmUUID)
        }
        return .result()
    }
}
