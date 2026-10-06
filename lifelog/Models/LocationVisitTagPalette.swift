//
//  LocationVisitTagPalette.swift
//  lifelog
//

import Foundation

/// Initial colors for location tags; assigned colors stay stored across rename and reorder.
/// See docs/ui-guidelines.md for the review map's tag color presentation.
enum LocationVisitTagPalette {
    static let hexColors = [
        "D87568", "C79558", "688EA8", "8C80AE",
        "B77D9B", "62A39A", "80A36D", "A7A65F",
        "A77E64", "7399B8", "AA8BBA", "C88685"
    ]

    static let untaggedHex = "8A8F98"

    static func defaultHex(for sortOrder: Int) -> String {
        hexColors[max(0, sortOrder) % hexColors.count]
    }

    /// Reuse the least-used initial color so deleting or reordering tags does not shift colors.
    static func automaticHex(existingHexes: [String]) -> String {
        let normalized = existingHexes.compactMap(normalizedHex)
        let counts = hexColors.map { hex in normalized.filter { $0 == hex }.count }
        let leastUsedCount = counts.min() ?? 0
        let index = counts.firstIndex(of: leastUsedCount) ?? 0
        return hexColors[index]
    }

    /// Accept a leading # and expand shorthand, but always store six uppercase HEX digits.
    static func normalizedHex(_ rawHex: String) -> String? {
        var value = rawHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6,
              value.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
              }) else {
            return nil
        }
        return value.uppercased()
    }
}
