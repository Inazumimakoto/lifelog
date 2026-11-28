import XCTest
@testable import lifelify

@MainActor
final class ReviewRequestManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ReviewRequestManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        if let suiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testShouldRequestReview_requiresInitialDaysAndMinimumActions() {
        let manager = ReviewRequestManager(defaults: defaults)
        let installDate = Date(timeIntervalSince1970: 1_700_000_000)

        manager.recordAppLaunch(now: installDate)
        defaults.set(5, forKey: "ReviewRequestManager.actionCount")

        let twoDaysLater = installDate.addingTimeInterval(2 * 86_400)
        XCTAssertFalse(manager.shouldRequestReview(now: twoDaysLater))

        let fourDaysLater = installDate.addingTimeInterval(4 * 86_400)
        XCTAssertTrue(manager.shouldRequestReview(now: fourDaysLater))
    }

    func testShouldRequestReview_respectsCooldownAfterLastRequest() {
        let manager = ReviewRequestManager(defaults: defaults)
        let installDate = Date(timeIntervalSince1970: 1_700_000_000)
        let firstRequestDate = installDate.addingTimeInterval(10 * 86_400)

        manager.recordAppLaunch(now: installDate)
        defaults.set(5, forKey: "ReviewRequestManager.actionCount")
        defaults.set(firstRequestDate, forKey: "ReviewRequestManager.lastRequestDate")

        let sixtyDaysAfterRequest = firstRequestDate.addingTimeInterval(60 * 86_400)
        XCTAssertFalse(manager.shouldRequestReview(now: sixtyDaysAfterRequest))

        let afterCooldown = firstRequestDate.addingTimeInterval(121 * 86_400)
        XCTAssertTrue(manager.shouldRequestReview(now: afterCooldown))
    }

    func testRecordAppLaunch_setsInitialDateOncePerInstall() {
        let manager = ReviewRequestManager(defaults: defaults)
        let firstLaunch = Date(timeIntervalSince1970: 1_700_000_000)
        let secondLaunch = firstLaunch.addingTimeInterval(5 * 86_400)

        manager.recordAppLaunch(now: firstLaunch)
        manager.recordAppLaunch(now: secondLaunch)

        let stored = defaults.object(forKey: "ReviewRequestManager.initialLaunchDate") as? Date
        XCTAssertEqual(stored, firstLaunch)
    }
}
