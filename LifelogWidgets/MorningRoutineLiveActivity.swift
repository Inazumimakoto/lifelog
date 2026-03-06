//
//  MorningRoutineLiveActivity.swift
//  LifelogWidgets
//

import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 17.0, *)
struct MorningRoutineLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MorningRoutineActivityAttributes.self) { context in
            MorningRoutineLiveActivityView(context: context)
                .widgetURL(URL(string: "lifelog://routine"))
                .activityBackgroundTint(Color(red: 0.97, green: 0.84, blue: 0.67))
                .activitySystemActionForegroundColor(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("朝ルーティン", systemImage: "sunrise.fill")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MorningRoutineExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MorningRoutineExpandedBottomView(context: context)
                }
            } compactLeading: {
                Image(systemName: "sunrise.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                MorningRoutineCompactTrailingView(context: context)
            } minimal: {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "lifelog://routine"))
        }
    }
}

@available(iOS 17.0, *)
private struct MorningRoutineLiveActivityView: View {
    let context: ActivityViewContext<MorningRoutineActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: context.attributes.startedAt, by: 1)) { timeline in
            let progress = MorningRoutineRuntime.progress(
                steps: context.attributes.steps,
                startingAt: context.attributes.startedAt,
                at: timeline.date
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.routineTitle)
                            .font(.headline)
                            .foregroundStyle(.black)

                        if let currentStep = progress.currentStep {
                            Text(currentStep.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.black)
                        } else {
                            Text("ルーティン完了")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.black)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("全体残り")
                            .font(.caption2)
                            .foregroundStyle(.black.opacity(0.65))
                        if let overallEndAt = progress.overallEndAt, progress.isFinished == false {
                            Text(overallEndAt, style: .timer)
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(.black)
                        } else {
                            Text("00:00")
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(.black)
                        }
                    }
                }

                if let currentStep = progress.currentStep {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("この工程の残り")
                            .font(.caption)
                            .foregroundStyle(.black.opacity(0.7))
                        Text(currentStep.endAt, style: .timer)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.black)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(progress.timeline.prefix(4)) { step in
                        stepChip(step: step, progress: progress)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func stepChip(step: MorningRoutineTimelineStep, progress: MorningRoutineProgress) -> some View {
        let isCurrent = progress.currentStep?.id == step.id
        let isDone = step.endAt <= Date()

        return VStack(alignment: .leading, spacing: 4) {
            Text(step.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(step.endAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.black.opacity(isDone ? 0.55 : 0.88))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Color.white.opacity(0.9) : Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

@available(iOS 17.0, *)
private struct MorningRoutineExpandedTrailingView: View {
    let context: ActivityViewContext<MorningRoutineActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: context.attributes.startedAt, by: 1)) { timeline in
            let progress = MorningRoutineRuntime.progress(
                steps: context.attributes.steps,
                startingAt: context.attributes.startedAt,
                at: timeline.date
            )

            if let overallEndAt = progress.overallEndAt, progress.isFinished == false {
                Text(overallEndAt, style: .timer)
                    .font(.headline.monospacedDigit())
            } else {
                Text("完了")
                    .font(.headline)
            }
        }
    }
}

@available(iOS 17.0, *)
private struct MorningRoutineExpandedBottomView: View {
    let context: ActivityViewContext<MorningRoutineActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: context.attributes.startedAt, by: 1)) { timeline in
            let progress = MorningRoutineRuntime.progress(
                steps: context.attributes.steps,
                startingAt: context.attributes.startedAt,
                at: timeline.date
            )

            VStack(alignment: .leading, spacing: 8) {
                if let currentStep = progress.currentStep {
                    Text("いま: \(currentStep.title)")
                        .font(.subheadline.weight(.semibold))
                    Text("終了 \(currentStep.endAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("すべて完了しました")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@available(iOS 17.0, *)
private struct MorningRoutineCompactTrailingView: View {
    let context: ActivityViewContext<MorningRoutineActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: context.attributes.startedAt, by: 1)) { timeline in
            let progress = MorningRoutineRuntime.progress(
                steps: context.attributes.steps,
                startingAt: context.attributes.startedAt,
                at: timeline.date
            )

            if let currentStep = progress.currentStep {
                Text(currentStep.endAt, style: .timer)
                    .font(.caption2.monospacedDigit())
            } else {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
        }
    }
}
