import Foundation
import Security

/// Local retirement only. Never reads credentials or contacts a server.
/// Letter encryption, Firebase sessions and the GitHub PAT use other services.
@MainActor
enum RetiredIntegrationCredentials {
    private static let completionKey = "retiredChatGPTCredentialsRemoved.v1"
    private static let services = [
        "com.inazumimakoto.lifelog.shopping.connection.dev",
        "com.inazumimakoto.lifelog.cloud.account.simulator"
    ]

    static func removeIfNeeded(
        defaults: UserDefaults = .standard,
        delete: ([String: Any]) -> OSStatus = { SecItemDelete($0 as CFDictionary) }
    ) {
        guard !defaults.bool(forKey: completionKey) else { return }
        // These markers belonged to settings sync. Native display/notification
        // preferences use different keys and must remain unchanged.
        for service in services {
            defaults.removeObject(forKey: service + ".settings.explicit.v1")
        }
        var completed = true
        for service in services {
            let status = delete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrSynchronizable as String: false
            ])
            if status != errSecSuccess && status != errSecItemNotFound {
                completed = false
            }
        }
        // A locked/unavailable Keychain is retried on the next foreground event.
        if completed { defaults.set(true, forKey: completionKey) }
    }
}
