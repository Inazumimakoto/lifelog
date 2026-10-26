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
        let sleepSegments = viewModel.sleepSegments
        var publications = 0
        let subscription = viewModel.objectWillChange.sink { publications += 1 }

        store.diaryEntries[0].text = "After"
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(viewModel.wellnessPoints, wellness)
        XCTAssertEqual(viewModel.correlationPoints, correlations)
        XCTAssertEqual(viewModel.sleepSegments, sleepSegments)
        withExtendedLifetime(subscription) {}
    }

    func testMoodEdit_updatesWellnessAndKeepsPointIdentityAndSleepSegments() async {
        let day = Calendar.current.startOfDay(for: Date())
        let store = PerformanceTestStore.make(health: [summary(on: day)])
        store.diaryEntries = [DiaryEntry(date: day, text: "", mood: .neutral, conditionScore: 3)]
        let viewModel = HealthViewModel(store: store)
        let originalIDs = viewModel.wellnessPoints.map(\.id)
        let sleepSegments = viewModel.sleepSegments
        var sleepPublications = 0
        var cancellables = Set<AnyCancellable>()
        viewModel.$sleepSegments.dropFirst().sink { _ in sleepPublications += 1 }.store(in: &cancellables)
        let updated = expectation(description: "Mood chart updated")
        viewModel.$wellnessPoints.dropFirst().sink { points in
            if points.first?.mood == .veryHigh { updated.fulfill() }
        }.store(in: &cancellables)

        store.diaryEntries[0].mood = .veryHigh
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.correlationPoints.first?.mood, .veryHigh)
        XCTAssertEqual(viewModel.wellnessPoints.first?.mood, .veryHigh)
        XCTAssertEqual(viewModel.wellnessPoints.map(\.id), originalIDs)
        XCTAssertEqual(viewModel.sleepSegments, sleepSegments)
        XCTAssertEqual(sleepPublications, 0)
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
        XCTAssertNil(viewModel.correlationPoints.first?.mood)
        XCTAssertNil(viewModel.correlationPoints.first?.condition)
        var publications = 0
        let subscription = viewModel.objectWillChange.sink { publications += 1 }

        store.diaryEntries[1].mood = .veryHigh
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertNil(viewModel.correlationPoints.first?.mood)
        XCTAssertNil(viewModel.wellnessPoints.first?.condition)
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

    func testSourceValues_keepOriginalUnitsAndStableDates() {
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
        XCTAssertEqual(viewModel.wellnessPoints.map(\.steps), [2_000, 4_000])
        XCTAssertEqual(viewModel.wellnessPoints.map(\.sleepHours), [4, 8])
        XCTAssertTrue(viewModel.wellnessPoints.allSatisfy { $0.mood == nil && $0.condition == nil })
    }

    func testDiaryOnlyDay_preservesScoresWithoutHealthMeasurements() {
        let day = Calendar.current.startOfDay(for: Date())
        let store = PerformanceTestStore.make()
        store.diaryEntries = [DiaryEntry(date: day, text: "", mood: .high, conditionScore: nil)]
        let viewModel = HealthViewModel(store: store)

        XCTAssertTrue(viewModel.summaries.isEmpty)
        XCTAssertTrue(viewModel.correlationPoints.isEmpty)
        XCTAssertEqual(viewModel.wellnessPoints.count, 1)
        XCTAssertEqual(viewModel.wellnessPoints.first?.id, day)
        XCTAssertEqual(viewModel.wellnessPoints.first?.mood, .high)
        XCTAssertNil(viewModel.wellnessPoints.first?.condition)
        XCTAssertNil(viewModel.wellnessPoints.first?.steps)
        XCTAssertNil(viewModel.wellnessPoints.first?.sleepHours)
    }

    func testPartialHealthDays_unionWithDiaryDaysAndKeepMissingMeasurements() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        var stepsOnly = HealthSummary(date: twoDaysAgo)
        stepsOnly.steps = 6_000
        var sleepOnly = HealthSummary(date: yesterday)
        sleepOnly.sleepHours = 7.5
        let store = PerformanceTestStore.make(health: [sleepOnly, stepsOnly])
        store.diaryEntries = [
            DiaryEntry(date: yesterday, text: "", mood: nil, conditionScore: 4),
            DiaryEntry(date: today, text: "", mood: .low, conditionScore: nil)
        ]
        let viewModel = HealthViewModel(store: store)

        XCTAssertEqual(viewModel.wellnessPoints.map(\.date), [twoDaysAgo, yesterday, today])
        XCTAssertEqual(viewModel.wellnessPoints.map(\.steps), [6_000, nil, nil])
        XCTAssertEqual(viewModel.wellnessPoints.map(\.sleepHours), [nil, 7.5, nil])
        XCTAssertEqual(viewModel.wellnessPoints.map(\.mood), [nil, nil, .low])
        XCTAssertEqual(viewModel.wellnessPoints.map(\.condition), [nil, 4, nil])
        XCTAssertTrue(viewModel.correlationPoints.isEmpty)
    }

    func testWeeklySummaries_filterLastSevenCalendarDaysAndExcludeFutureRecords() {
        let calendar = fixedCalendar()
        let today = date(2026, 10, 13, calendar: calendar)
        let current = calendar.date(byAdding: .day, value: -2, to: today)!
        let firstDay = calendar.date(byAdding: .day, value: -6, to: today)!
        let old = calendar.date(byAdding: .day, value: -7, to: today)!
        let future = calendar.date(byAdding: .day, value: 1, to: today)!
        let store = PerformanceTestStore.make(health: [future, today, current, firstDay, old].map { summary(on: $0) })
        let viewModel = HealthViewModel(store: store, calendarProvider: { calendar }, dateProvider: { today })

        XCTAssertEqual(viewModel.summaries.map(\.date), [old, firstDay, current, today, future])
        XCTAssertEqual(viewModel.weeklySummaries.map(\.date), [firstDay, current, today])
        XCTAssertEqual(viewModel.weeklyWellnessPoints.map(\.date), [firstDay, current, today])
    }

    func testAverages_excludeMissingValuesAndPreserveMeasuredZero() {
        let calendar = fixedCalendar()
        let today = date(2026, 10, 13, calendar: calendar)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        var measured = HealthSummary(date: day(-2))
        measured.steps = 6_000
        measured.sleepHours = 8
        measured.activeEnergy = 300
        measured.exerciseMinutes = 20
        measured.standHours = 8
        var zero = HealthSummary(date: day(-1))
        zero.steps = 0
        zero.activeEnergy = 0
        let missing = HealthSummary(date: today)
        let store = PerformanceTestStore.make(health: [missing, zero, measured])
        let viewModel = HealthViewModel(store: store, calendarProvider: { calendar }, dateProvider: { today })

        XCTAssertEqual(viewModel.averageSteps, 3_000)
        XCTAssertEqual(viewModel.averageSleep, 8)
        XCTAssertEqual(viewModel.averageActiveEnergy, 150)
        XCTAssertEqual(viewModel.averageExerciseMinutes, 20)
        XCTAssertEqual(viewModel.averageStandHours, 8)
        XCTAssertEqual(viewModel.averageMoveMinutes, 0)
        XCTAssertNil(viewModel.weeklySummaries.last?.steps)
        XCTAssertNil(viewModel.weeklySummaries.last?.sleepHours)
        XCTAssertNil(viewModel.weeklySummaries.last?.activeEnergy)
        XCTAssertNil(viewModel.weeklySummaries.last?.exerciseMinutes)
    }

    func testSameCalendarDay_normalizesNewestMeasurementsWithoutLosingMissingGoals() {
        let calendar = fixedCalendar()
        let today = date(2026, 10, 13, calendar: calendar)
        let empty = HealthSummary(date: today)
        var earlier = HealthSummary(date: today.addingTimeInterval(3_600))
        earlier.steps = 3_000
        earlier.sleepHours = 7
        earlier.activeEnergy = 320
        earlier.activeEnergyGoal = 450
        earlier.exerciseMinutesGoal = 30
        earlier.standHoursGoal = 12
        earlier.fitnessMoveMode = .energy
        var later = HealthSummary(date: today.addingTimeInterval(7_200))
        later.steps = 5_000
        later.activeEnergy = 420
        later.exerciseMinutesGoal = 35
        var weatherOnly = HealthSummary(date: today.addingTimeInterval(10_800))
        weatherOnly.weatherCondition = "Clear"
        let store = PerformanceTestStore.make(health: [later, empty, weatherOnly, earlier])
        let viewModel = HealthViewModel(store: store, calendarProvider: { calendar }, dateProvider: { today })

        XCTAssertEqual(viewModel.summaries.count, 1)
        XCTAssertEqual(viewModel.summaries.first?.date, today)
        XCTAssertEqual(viewModel.averageSteps, 5_000)
        XCTAssertEqual(viewModel.averageSleep, 7)
        XCTAssertEqual(viewModel.averageActiveEnergy, 420)
        XCTAssertEqual(viewModel.summaries.first?.activeEnergyGoal, 450)
        XCTAssertEqual(viewModel.summaries.first?.exerciseMinutesGoal, 35)
        XCTAssertEqual(viewModel.summaries.first?.standHoursGoal, 12)
        XCTAssertEqual(viewModel.summaries.first?.fitnessMoveMode, .energy)
        XCTAssertEqual(viewModel.summaries.first?.weatherCondition, "Clear")
        XCTAssertEqual(viewModel.wellnessPoints.count, 1)
        XCTAssertEqual(viewModel.correlationPoints.count, 1)
        XCTAssertEqual(store.healthSummaries.count, 4)
    }

    func testSameDayGoalRefresh_preservesExplicitZeroAndLeavesUnfetchedGoalsNil() {
        let calendar = fixedCalendar()
        let today = date(2026, 10, 13, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        var earlier = HealthSummary(date: today)
        earlier.activeEnergyGoal = 450
        earlier.exerciseMinutesGoal = 30
        var noGoal = HealthSummary(date: today.addingTimeInterval(3_600))
        noGoal.activeEnergyGoal = 0
        noGoal.exerciseMinutesGoal = 0
        let missing = HealthSummary(date: today.addingTimeInterval(7_200))
        let unfetched = HealthSummary(date: yesterday)
        let store = PerformanceTestStore.make(health: [missing, noGoal, earlier, unfetched])
        let viewModel = HealthViewModel(store: store, calendarProvider: { calendar }, dateProvider: { today })

        XCTAssertEqual(viewModel.summaries.count, 2)
        XCTAssertEqual(viewModel.summaries.last?.activeEnergyGoal, 0)
        XCTAssertEqual(viewModel.summaries.last?.exerciseMinutesGoal, 0)
        XCTAssertNil(viewModel.summaries.first?.activeEnergyGoal)
        XCTAssertNil(viewModel.summaries.first?.exerciseMinutesGoal)
    }

    func testTimeZoneChange_coalescesOldAndNewMidnightsBeforeAveraging() async {
        var calendar = fixedCalendar()
        let tokyoMidnight = date(2026, 10, 13, calendar: calendar)
        let destinationCalendar = fixedCalendar(timeZone: "America/Los_Angeles")
        let losAngelesMidnight = date(2026, 10, 12, calendar: destinationCalendar)
        var older = HealthSummary(date: losAngelesMidnight)
        older.steps = 4_000
        older.sleepHours = 7
        older.activeEnergy = 300
        older.activeEnergyGoal = 450
        older.exerciseMinutesGoal = 30
        var newer = HealthSummary(date: tokyoMidnight)
        newer.steps = 6_000
        newer.activeEnergy = 500
        newer.standHoursGoal = 12
        let empty = HealthSummary(date: losAngelesMidnight.addingTimeInterval(3_600))
        let store = PerformanceTestStore.make(health: [newer, empty, older])
        let notifications = NotificationCenter()
        let viewModel = HealthViewModel(store: store, calendarProvider: { calendar },
                                        dateProvider: { tokyoMidnight }, notificationCenter: notifications)
        XCTAssertEqual(viewModel.summaries.count, 2)
        let updated = expectation(description: "One destination calendar day")
        let subscription = viewModel.$summaries.dropFirst().sink { summaries in
            if summaries.count == 1, summaries.first?.date == losAngelesMidnight { updated.fulfill() }
        }

        calendar = destinationCalendar
        notifications.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.weeklySummaries.count, 1)
        XCTAssertEqual(viewModel.averageSteps, 6_000)
        XCTAssertEqual(viewModel.averageSleep, 7)
        XCTAssertEqual(viewModel.averageActiveEnergy, 500)
        XCTAssertEqual(viewModel.summaries.first?.activeEnergyGoal, 450)
        XCTAssertEqual(viewModel.summaries.first?.exerciseMinutesGoal, 30)
        XCTAssertEqual(viewModel.summaries.first?.standHoursGoal, 12)
        XCTAssertEqual(viewModel.wellnessPoints.map(\.id), [losAngelesMidnight])
        XCTAssertEqual(viewModel.wellnessPoints.first?.steps, 6_000)
        XCTAssertEqual(store.healthSummaries.count, 3)
        withExtendedLifetime(subscription) {}
    }

    func testDayChange_advancesWeeklyWindowWithoutChangingSourceData() async {
        let calendar = fixedCalendar()
        var referenceDate = date(2026, 10, 13, calendar: calendar)
        let oldest = calendar.date(byAdding: .day, value: -6, to: referenceDate)!
        let newest = referenceDate
        let notifications = NotificationCenter()
        let store = PerformanceTestStore.make(health: [summary(on: newest), summary(on: oldest)])
        let viewModel = HealthViewModel(store: store, calendarProvider: { calendar },
                                        dateProvider: { referenceDate }, notificationCenter: notifications)
        XCTAssertEqual(viewModel.weeklySummaries.map(\.date), [oldest, newest])

        referenceDate = calendar.date(byAdding: .day, value: 1, to: referenceDate)!
        notifications.post(name: .NSCalendarDayChanged, object: nil)
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertEqual(viewModel.weeklySummaries.map(\.date), [newest])
        XCTAssertEqual(viewModel.summaries.count, 2)
    }

    func testHistoryPeriods_includeSelectedDayAndExcludeFollowingDay() {
        let calendar = fixedCalendar()
        let selectedDate = date(2026, 10, 13, hour: 16, calendar: calendar)
        let expectedEnd = date(2026, 10, 14, calendar: calendar)
        let expectations: [(HealthHistoryPeriod, Date)] = [
            (.week, date(2026, 10, 7, calendar: calendar)),
            (.month, date(2026, 9, 14, calendar: calendar)),
            (.halfYear, date(2026, 4, 14, calendar: calendar)),
            (.year, date(2025, 10, 14, calendar: calendar))
        ]
        for (period, expectedStart) in expectations {
            let range = period.dateRange(endingOn: selectedDate, calendar: calendar)
            XCTAssertEqual(range.lowerBound, expectedStart, "\(period)")
            XCTAssertEqual(range.upperBound, expectedEnd, "\(period)")
            XCTAssertTrue(range.contains(selectedDate), "\(period)")
            XCTAssertFalse(range.contains(expectedEnd), "\(period)")
        }
    }

    func testHistoryMonthNavigation_restoresOriginalMonthEndAfterRoundTrip() {
        let calendar = fixedCalendar()
        let monthEnd = date(2026, 3, 31, calendar: calendar)
        var position = HealthHistoryPosition(period: .month, endingOn: monthEnd, calendar: calendar)

        position.move(by: -1, latestDate: monthEnd, calendar: calendar)
        XCTAssertEqual(position.endingOn(calendar: calendar), date(2026, 2, 28, calendar: calendar))
        position.move(by: 1, latestDate: monthEnd, calendar: calendar)

        XCTAssertEqual(position.endingOn(calendar: calendar), monthEnd)
        XCTAssertEqual(position.offset, 0)
    }

    func testHistoryYearNavigation_restoresLeapDayAfterRoundTrip() {
        let calendar = fixedCalendar()
        let leapDay = date(2024, 2, 29, calendar: calendar)
        var position = HealthHistoryPosition(period: .year, endingOn: leapDay, calendar: calendar)

        position.move(by: -1, latestDate: leapDay, calendar: calendar)
        XCTAssertEqual(position.endingOn(calendar: calendar), date(2023, 2, 28, calendar: calendar))
        position.move(by: 1, latestDate: leapDay, calendar: calendar)

        XCTAssertEqual(position.endingOn(calendar: calendar), leapDay)
        XCTAssertEqual(position.offset, 0)
    }

    func testHistoryScaleChange_keepsCurrentEndingDayAndStartsNewOffset() {
        let calendar = fixedCalendar()
        let monthEnd = date(2026, 3, 31, calendar: calendar)
        let currentEnd = date(2026, 2, 28, calendar: calendar)
        var position = HealthHistoryPosition(period: .month, endingOn: monthEnd, calendar: calendar)
        position.move(by: -1, latestDate: monthEnd, calendar: calendar)

        position.changePeriod(to: .week, calendar: calendar)

        XCTAssertEqual(position.period, .week)
        XCTAssertEqual(position.endingOn(calendar: calendar), currentEnd)
        XCTAssertEqual(position.offset, 0)
        position.move(by: -1, latestDate: monthEnd, calendar: calendar)
        XCTAssertEqual(position.endingOn(calendar: calendar), date(2026, 2, 21, calendar: calendar))
        position.move(by: 1, latestDate: monthEnd, calendar: calendar)
        XCTAssertEqual(position.endingOn(calendar: calendar), currentEnd)
    }

    func testHistoryNavigation_clampsToLatestDayWithoutShowingFuture() {
        let calendar = fixedCalendar()
        let latest = date(2026, 10, 13, hour: 16, calendar: calendar)
        var position = HealthHistoryPosition(period: .month,
                                             endingOn: date(2026, 9, 30, calendar: calendar), calendar: calendar)

        position.move(by: 1, latestDate: latest, calendar: calendar)

        XCTAssertEqual(position.endingOn(calendar: calendar), calendar.startOfDay(for: latest))
        XCTAssertEqual(position.referenceDate, calendar.startOfDay(for: latest))
        XCTAssertEqual(position.offset, 0)
    }

    func testSleepDurationAndWeekWindow_useElapsedTimeAcrossDaylightSaving() {
        let calendar = fixedCalendar(timeZone: "America/Los_Angeles")
        let start = date(2026, 3, 7, hour: 23, calendar: calendar)
        let end = date(2026, 3, 8, hour: 7, calendar: calendar)
        let segment = SleepSegment(date: calendar.startOfDay(for: end), start: start, end: end)
        let range = HealthHistoryPeriod.week.dateRange(endingOn: date(2026, 3, 9, calendar: calendar), calendar: calendar)

        XCTAssertEqual(segment.durationHours, 7, accuracy: 0.001)
        XCTAssertEqual(calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day, 7)
        XCTAssertEqual(range.upperBound.timeIntervalSince(range.lowerBound) / 3_600, 167, accuracy: 0.001)
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
        let originalCorrelation = viewModel.correlationPoints.first
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

        XCTAssertEqual(viewModel.summaries.first?.date, newDay)
        XCTAssertEqual(viewModel.correlationPoints.first?.id, newDay)
        XCTAssertEqual(viewModel.correlationPoints.first?.steps, originalCorrelation?.steps)
        XCTAssertEqual(viewModel.correlationPoints.first?.sleepHours, originalCorrelation?.sleepHours)
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

    private func fixedCalendar(timeZone: String = "Asia/Tokyo") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
