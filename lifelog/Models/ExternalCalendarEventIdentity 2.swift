import Foundation
import CryptoKit

/// EventKit identifiers describe a series; the occurrence date distinguishes its
/// repeated instances. Stable IDs keep a refresh from replacing every visible row.
nonisolated enum ExternalCalendarEventIdentity {
    static func id(calendarIdentifier: String, eventIdentifier: String, occurrenceDate: Date?) -> UUID {
        // A nonrecurring event needs only its source identifier; moving its
        // start time should preserve identity just as a detached occurrence does.
        let occurrence = occurrenceDate.map { String($0.timeIntervalSince1970.bitPattern) } ?? "single"
        let fields = [calendarIdentifier, eventIdentifier, occurrence]
        let key = fields.map { "\($0.utf8.count):\($0)" }.joined()
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        // UUID version 8 reserves custom deterministic layouts; retain the RFC variant.
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
