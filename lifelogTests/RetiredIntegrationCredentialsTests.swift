import Foundation
import Security
import XCTest
@testable import lifelify

@MainActor
final class RetiredIntegrationCredentialsTests: XCTestCase {
    func testRemoval_targetsOnlyDedicatedLocalServicesWithoutReadingOtherSecrets() throws {
        let defaults = try makeDefaults()
        let markers = [
            "com.inazumimakoto.lifelog.shopping.connection.dev.settings.explicit.v1",
            "com.inazumimakoto.lifelog.cloud.account.simulator.settings.explicit.v1"
        ]
        for marker in markers { defaults.set(["diaryReminderEnabled"], forKey: marker) }
        defaults.set(true, forKey: "diaryReminderEnabled")
        defaults.set("original", forKey: "WallpaperCalendar_Settings_V1")
        var queries: [[String: Any]] = []
        RetiredIntegrationCredentials.removeIfNeeded(defaults: defaults) { query in
            queries.append(query)
            return errSecSuccess
        }
        XCTAssertEqual(Set(queries.compactMap { $0[kSecAttrService as String] as? String }), [
            "com.inazumimakoto.lifelog.shopping.connection.dev",
            "com.inazumimakoto.lifelog.cloud.account.simulator"
        ])
        for query in queries {
            XCTAssertEqual(query.count, 3)
            XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
            XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        }
        for marker in markers { XCTAssertNil(defaults.object(forKey: marker)) }
        XCTAssertTrue(defaults.bool(forKey: "diaryReminderEnabled"))
        XCTAssertEqual(defaults.string(forKey: "WallpaperCalendar_Settings_V1"), "original")
        RetiredIntegrationCredentials.removeIfNeeded(defaults: defaults) { _ in
            XCTFail("Successful retirement must not keep issuing deletion queries")
            return errSecSuccess
        }
    }

    func testUnavailableKeychain_retriesUntilEveryDedicatedServiceIsRemoved() throws {
        let defaults = try makeDefaults()
        var attempts = 0
        RetiredIntegrationCredentials.removeIfNeeded(defaults: defaults) { _ in
            attempts += 1
            return attempts == 1 ? errSecInteractionNotAllowed : errSecSuccess
        }
        RetiredIntegrationCredentials.removeIfNeeded(defaults: defaults) { _ in
            attempts += 1
            return errSecItemNotFound
        }
        XCTAssertEqual(attempts, 4)
        RetiredIntegrationCredentials.removeIfNeeded(defaults: defaults) { _ in
            XCTFail("Missing retired items count as completed cleanup")
            return errSecSuccess
        }
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "RetiredIntegrationCredentialsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}
