import Foundation

/// One normalization rule for persisted identities, tag lookup and canonical filter keys.
nonisolated enum ReviewMapCacheIdentity {
    static let untaggedFilterToken = "__untagged__"
    static let untaggedColorHex = "8A8F98"

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func placeID(for location: ReviewMapLocationSource) -> String {
        if let url = location.mapItemURL, !url.isEmpty {
            return "mapitem:\(url)"
        }
        let latitude = (location.latitude * 10_000).rounded() / 10_000
        let longitude = (location.longitude * 10_000).rounded() / 10_000
        return "coord:\(latitude),\(longitude):\(normalizedName(location.name))"
    }

    static func normalizedColorHex(_ colorHex: String) -> String {
        var value = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6, value.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { return untaggedColorHex }
        return value.uppercased()
    }
}
