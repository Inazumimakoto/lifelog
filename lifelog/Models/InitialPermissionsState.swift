//
//  InitialPermissionsState.swift
//  lifelog
//
//  Created by Codex on 2026/05/02.
//

import Foundation

enum InitialPermissionsState {
    static let completedKey = "initialPermissionsSetupCompletedV1"
    static let featureSeenKey = "initialPermissionsSetupFeatureSeenV1"
    static let notificationRequestedKey = "initialPermissionsNotificationRequestedV1"
    static let locationRequestedKey = "initialPermissionsLocationRequestedV1"
    static let calendarRequestedKey = "initialPermissionsCalendarRequestedV1"
    static let healthRequestedKey = "initialPermissionsHealthRequestedV1"
}
