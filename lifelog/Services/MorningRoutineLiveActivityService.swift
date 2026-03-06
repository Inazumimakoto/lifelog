//
//  MorningRoutineLiveActivityService.swift
//  lifelog
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

final class MorningRoutineLiveActivityService {
    static let shared = MorningRoutineLiveActivityService()

    private init() {}

    func start(session: MorningRoutineSession) async throws {
        guard #available(iOS 17.0, *) else { return }

        await end(sessionID: nil)

        let attributes = MorningRoutineActivityAttributes(
            sessionID: session.id,
            routineTitle: session.title,
            startedAt: session.startedAt,
            steps: session.steps
        )
        let content = ActivityContent(
            state: MorningRoutineActivityAttributes.ContentState(isRunning: true),
            staleDate: session.plannedEndAt
        )

        _ = try Activity<MorningRoutineActivityAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    func end(sessionID: UUID?) async {
        guard #available(iOS 17.0, *) else { return }

        for activity in Activity<MorningRoutineActivityAttributes>.activities {
            guard sessionID == nil || activity.attributes.sessionID == sessionID else {
                continue
            }

            let finalContent = ActivityContent(
                state: MorningRoutineActivityAttributes.ContentState(isRunning: false),
                staleDate: nil
            )
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
    }
}
