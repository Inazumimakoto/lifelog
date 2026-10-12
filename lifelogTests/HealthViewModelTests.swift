import Combine
import XCTest
@testable import lifelify

@MainActor
final class HealthViewModelTests: XCTestCase {
    func testDiaryTextEdit_doesNotRepublishHealthCharts() async {
        let day = Calendar.current.startOfDay(for: Date())
        let store = PerformanceTestStore.make(health: [summary(on: day)])
        store.diaryEntries = [DiaryEntry(date: day, text: "Before", mood: .high, conditionScore: 4)]
        let viewModel = HealthViewModel(store: store)
        let wellness = viewModel.wellnessPoints
        let correlations = viewModel.correlationPoints
        let quality = viewModel.sleepQualityPoints
        var publications = 0
        let subscription = viewModel.objectWillChange.sink { publications += 1 }

        store.diaryEntries[0].text = "After"
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(viewModel.wellnessPoints, wellness)
        XCTAssertEqual(viewModel.correlationPoints, correlations)
        XCTAssertEqual(viewModel.sleepQualityPoints, quality)
        withExtendedLifetime(subscription) {}
    }

    func testMoodEdit_updatesWellnessAndKeepsPointIdentityAndSleepCurve() async {
        let day = Calendar.current.startOfDay(for: Date())
        let store = PerformanceTestStore.make(health: [summary(on: day)])
        store.diaryEntries = [DiaryEntry(date: day, text: "", mood: .neutral, conditionScore: 3)]
        let viewModel = HealthViewModel(store: store)
        let originalIDs = viewModel.wellnessPoints.map(\.id)
        let sleepCurve = viewModel.sleepQualityPoints
        var qualityPublications = 0
        var cancellables = Set<AnyCancellable>()
        viewModel.$sleepQualityPoints.dropFirst().sink { _ in qualityPublications += 1 }.store(in: &cancellables)
        let updated = expectation(description: "Mood chart updated")
        viewModel.$wellnessPoints.dropFirst().sink { points in
            if points.first?.moodPercent == 100 { updated.fulfill() }
        }.store(in: &cancellables)

        store.diaryEntries[0].mood = .veryHigh
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.correlationPoints.first?.mood, .veryHigh)
        XCTAssertEqual(viewModel.wellnessPoints.first?.moodPercent, 100)
        XCTAssertEqual(viewModel.wellnessPoints.map(\.id), originalIDs)
        XCTAssertEqual(viewModel.sleepQualityPoints, sleepCurve)
        XCTAssertEqual(qualityPublications, 0)
        withExtendedLifetime(cancellables) {}
    }

    func testDuplicateDiaryDates_keepFirstRecordAndIgnoreSecondMoodChanges() async {
        let day = Calendar.current.startOfDay(for: Date())
        let store = PerformanceTestStore.make(health: [summary(on: day)])
        store.diaryEntries = [
            DiaryEntry(date: day, text: "First", mood: nil, conditionScore: nil),
            DiaryEntry(date: day.addingTimeInterval(3_600), text: "Second", mood: .high, conditionScore: 5)
        ]
        let viewModel = HealthViewModel(store: store)
        XCTAssertEqual(viewModel.correlationPoints.first?.mood, .neutral)
        XCTAssertEqual(viewModel.correlationPoints.first?.condition, 3)
        var publications = 0
        let subscription = viewModel.objectWillChange.sink { publications += 1 }

        store.diaryEntries[1].mood = .veryHigh
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertEqual(viewModel.correlationPoints.first?.mood, .neutral)
        XCTAssertEqual(publications, 0)
        withExtendedLifetime(subscription) {}
    }

    func testWeatherRefresh_updatesSummariesWithoutReplacingWellnessPoints() async {
        let day = Calendar.current.startOfDay(for: Date())
        let store = PerformanceTestStore.make(health: [summary(on: day)])
        let viewModel = HealthViewModel(store: store)
        let originalWellness = viewModel.wellnessPoints
        var wellnessPublications = 0
        var cancellables = Set<AnyCancellable>()
        viewModel.$wellnessPoints.dropFirst().sink { _ in wellnessPublications += 1 }.store(in: &cancellables)
        let updated = expectation(description: "Source health summary updated")
        viewModel.$summaries.dropFirst().sink { summaries in
            if summaries.first?.weatherCondition == "Clear" { updated.fulfill() }
        }.store(in: &cancellables)

        store.updateWeather(for: day, condition: "Clear", high: 25, low: 15)
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.summaries.first?.weatherCondition, "Clear")
        XCTAssertEqual(viewModel.wellnessPoints, originalWellness)
        XCTAssertEqual(wellnessPublications, 0)
        withExtendedLifetime(cancellables) {}
    }

    func testSourceValues_normalizeAcrossDaysAndUseStableDates() {
        let day = Calendar.current.startOfDay(for: Date())
        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        var earlier = summary(on: previousDay)
        earlier.steps = 2_000
        earlier.sleepHours = 4
        var later = summary(on: day)
        later.steps = 4_000
        later.sleepHours = 8
        let store = PerformanceTestStore.make(health: [later, earlier])
        let viewModel = HealthViewModel(store: store)

        XCTAssertEqual(viewModel.wellnessPoints.map(\.id), [previousDay, day])
        XCTAssertEqual(viewModel.wellnessPoints.map(\.stepsPercent), [50, 100])
        XCTAssertEqual(viewModel.wellnessPoints.map(\.sleepPercent), [50, 100])
        XCTAssertTrue(viewModel.wellnessPoints.allSatisfy { $0.mood == nil && $0.condition == nil })
    }

    func testTimeZoneNotification_rebuildsDayIdentityWithUnchangedSourceValues() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let instant = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23))!
        let originalDay = calendar.startOfDay(for: instant)
        let store = PerformanceTestStore.make(health: [summary(on: instant)])
        store.diaryEntries = [DiaryEntry(date: instant, text: "", mood: .high, conditionScore: 4)]
        let notifications = NotificationCenter()
        let viewModel = HealthViewModel(store: store,
                                        calendarProvider: { calendar },
                                        notificationCenter: notifications)
        let originalCorrelations = viewModel.correlationPoints
        XCTAssertEqual(viewModel.wellnessPoints.first?.id, originalDay)
        let updated = expectation(description: "Timezone updates normalized wellness day")
        var newCalendar = calendar
        newCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let newDay = newCalendar.startOfDay(for: instant)
        XCTAssertNotEqual(originalDay, newDay)
        let subscription = viewModel.$wellnessPoints.dropFirst().sink { points in
            if points.first?.id == newDay { updated.fulfill() }
        }

        calendar = newCalendar
        notifications.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.correlationPoints, originalCorrelations)
        XCTAssertEqual(viewModel.wellnessPoints.first?.id, newDay)
        XCTAssertEqual(viewModel.wellnessPoints.first?.mood, .high)
        XCTAssertEqual(viewModel.wellnessPoints.first?.steps, 4_000)
        withExtendedLifetime(subscription) {}
    }

    private func summary(on day: Date) -> HealthSummary {
        var summary = HealthSummary(date: day)
        summary.steps = 4_000
        summary.sleepHours = 8
        summary.sleepStart = day
        summary.sleepEnd = day.addingTimeInterval(8 * 3_600)
        return summary
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
