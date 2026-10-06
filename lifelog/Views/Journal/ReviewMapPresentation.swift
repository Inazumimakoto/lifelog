import Foundation
import CoreGraphics

/// Review-map display rules (docs/requirements.md §4.4.2, docs/ui-guidelines.md §Diary).
/// A point represents one place; its size represents distinct recorded days in the active filter.
enum ReviewMapPresentation {
    static let untaggedFilterToken = "__untagged__"

    static func markerDiameter(for count: Int, expanded: Bool) -> CGFloat {
        let increment: CGFloat = count >= 5 ? 2 : (count >= 2 ? 1 : 0)
        return (expanded ? 14 : 6) + increment
    }

    static func updateZoomState(distance: Double,
                                wasExpanded: Bool,
                                wereDatesVisible: Bool) -> (expanded: Bool, datesVisible: Bool) {
        // Separate entry/exit thresholds avoid flickering at a zoom boundary.
        let expanded = distance <= (wasExpanded ? 9_000 : 7_000)
        let datesVisible = distance <= (wereDatesVisible ? 3_200 : 2_500)
        return (expanded, datesVisible)
    }

    static func filteredGroups(_ groups: [ReviewLocationGroup],
                               selectedFilters: [String]) -> [ReviewLocationGroup] {
        guard !selectedFilters.isEmpty else { return groups }
        let selectedKeys = Set(selectedFilters.map(tagKey))
        return groups.compactMap { group in
            let visits = group.visits.filter { visit in
                (selectedKeys.contains(untaggedFilterToken) && visit.tags.isEmpty) ||
                    visit.tags.contains { selectedKeys.contains(tagKey($0)) }
            }
            guard !visits.isEmpty else { return nil }
            return ReviewLocationGroup(id: group.id, location: group.location, visits: visits)
        }
    }

    static func dominantTagName(for group: ReviewLocationGroup,
                                definitions: [LocationVisitTagDefinition],
                                selectedFilters: [String]) -> String? {
        rankedTagNames(for: group, definitions: definitions, selectedFilters: selectedFilters).first
    }

    static func tagNames(for group: ReviewLocationGroup,
                         definitions: [LocationVisitTagDefinition],
                         selectedFilters: [String]) -> [String] {
        // Choose the most frequent nine, then keep their positions stable rather than rotating
        // the segments whenever their frequency changes.
        let names = rankedTagNames(for: group, definitions: definitions, selectedFilters: selectedFilters)
        let order = tagOrder(definitions)
        return Array(names.prefix(9)).sorted { precedes($0, $1, order: order) }
    }

    static func colorHex(for tagName: String?, definitions: [LocationVisitTagDefinition]) -> String {
        guard let tagName,
              let definition = definitions.first(where: { tagKey($0.name) == tagKey(tagName) }) else {
            return LocationVisitTagPalette.untaggedHex
        }
        return definition.colorHex
    }

    private static func rankedTagNames(for group: ReviewLocationGroup,
                                       definitions: [LocationVisitTagDefinition],
                                       selectedFilters: [String]) -> [String] {
        let selectedKeys = Set(selectedFilters.map(tagKey))
        var frequency: [String: Int] = [:]
        var names: [String: String] = [:]
        for visit in group.visits {
            var seen: Set<String> = []
            for name in visit.tags {
                let key = tagKey(name)
                guard selectedKeys.isEmpty || selectedKeys.contains(key),
                      seen.insert(key).inserted else { continue }
                frequency[key, default: 0] += 1
                names[key] = name
            }
        }
        let order = tagOrder(definitions)
        return names.values.sorted { lhs, rhs in
            let leftCount = frequency[tagKey(lhs), default: 0]
            let rightCount = frequency[tagKey(rhs), default: 0]
            if leftCount != rightCount { return leftCount > rightCount }
            return precedes(lhs, rhs, order: order)
        }
    }

    private static func tagOrder(_ definitions: [LocationVisitTagDefinition]) -> [String: Int] {
        var order: [String: Int] = [:]
        for (index, definition) in definitions.sorted(by: {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }).enumerated() {
            order[tagKey(definition.name)] = index
        }
        return order
    }

    private static func precedes(_ lhs: String, _ rhs: String, order: [String: Int]) -> Bool {
        let leftOrder = order[tagKey(lhs), default: Int.max]
        let rightOrder = order[tagKey(rhs), default: Int.max]
        if leftOrder != rightOrder { return leftOrder < rightOrder }
        return tagKey(lhs) < tagKey(rhs)
    }

    private static func tagKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
