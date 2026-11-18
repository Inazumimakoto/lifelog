import Foundation

/// EventKit identifiers can change after a full calendar sync. Keep the saved
/// selections independently of today's inventory and recover only identities
/// that have one unambiguous match in both inventories.
/// See docs/requirements.md §Settings (external calendar category selections).
@MainActor
enum CalendarLinkReconciler {
    struct Result {
        var links: [CalendarCategoryLink]
        var unavailableLinks: [CalendarCategoryLink]
    }

    static func reconcile(
        calendars: [CalendarCategoryLink],
        links: [CalendarCategoryLink],
        unavailableLinks: [CalendarCategoryLink],
        defaultCategory: (String) -> String?
    ) -> Result {
        let inventory = uniqueIdentifiers(in: calendars)
        let previousLinks = uniqueIdentifiers(in: links)
        let savedLinks = uniqueIdentifiers(in: previousLinks + unavailableLinks)
        let savedIndices = Dictionary(uniqueKeysWithValues: savedLinks.enumerated().map {
            ($0.element.calendarIdentifier, $0.offset)
        })
        let inventoryIndices = Dictionary(uniqueKeysWithValues: inventory.enumerated().map {
            ($0.element.calendarIdentifier, $0.offset)
        })
        let savedTitleCounts = Dictionary(grouping: savedLinks, by: \.calendarTitle).mapValues(\.count)
        let inventoryTitleCounts = Dictionary(grouping: inventory, by: \.calendarTitle).mapValues(\.count)
        let availableSourceIdentifiers = Set(inventory.compactMap { nonempty($0.sourceIdentifier) })
        let savedSourceIdentifiers = Set(savedLinks.compactMap { nonempty($0.sourceIdentifier) })
        var assignments: [Int: Int] = [:]
        var usedSavedIndices = Set<Int>()

        // Exact IDs take priority, including calendars returning from an
        // unavailable state. A title or account rename does not change this.
        for (index, calendar) in inventory.enumerated() {
            guard let savedIndex = savedIndices[calendar.calendarIdentifier] else { continue }
            assignments[index] = savedIndex
            usedSavedIndices.insert(savedIndex)
        }

        func commonPropertiesMatch(_ saved: CalendarCategoryLink, _ calendar: CalendarCategoryLink) -> Bool {
            guard saved.calendarTitle == calendar.calendarTitle else { return false }
            if let savedType = saved.calendarTypeRawValue,
               let currentType = calendar.calendarTypeRawValue,
               savedType != currentType {
                return false
            }
            if let savedType = saved.sourceTypeRawValue,
               let currentType = calendar.sourceTypeRawValue,
               savedType != currentType {
                return false
            }
            return true
        }

        func sourceIdentifierMatches(_ saved: CalendarCategoryLink, _ calendar: CalendarCategoryLink) -> Bool {
            guard commonPropertiesMatch(saved, calendar),
                  let savedIdentifier = nonempty(saved.sourceIdentifier),
                  let currentIdentifier = nonempty(calendar.sourceIdentifier) else { return false }
            return savedIdentifier == currentIdentifier
        }

        func fallbackMatches(_ saved: CalendarCategoryLink, _ calendar: CalendarCategoryLink) -> Bool {
            guard commonPropertiesMatch(saved, calendar) else { return false }

            // Old installations have only calendar titles. Count the full old
            // and new inventories, including exact matches, so an existing
            // same-name calendar cannot cause another one's setting to move.
            if !hasSourceMetadata(saved) {
                return savedTitleCounts[saved.calendarTitle] == 1 &&
                    inventoryTitleCounts[calendar.calendarTitle] == 1
            }
            guard hasSourceMetadata(calendar) else { return false }
            // An account ID still present on any current calendar identifies
            // an existing account. Its missing calendar must not be attached
            // to a different account just because both are called "Gmail".
            if let savedIdentifier = nonempty(saved.sourceIdentifier),
               availableSourceIdentifiers.contains(savedIdentifier) {
                return false
            }
            if let savedIdentifier = nonempty(saved.sourceIdentifier),
               let currentIdentifier = nonempty(calendar.sourceIdentifier),
               savedIdentifier != currentIdentifier,
               savedSourceIdentifiers.contains(currentIdentifier) {
                return false
            }

            // Source IDs can change along with calendar IDs. Account name and
            // account type must both match before using that fallback.
            guard let savedTitle = nonempty(saved.sourceTitle),
                  let currentTitle = nonempty(calendar.sourceTitle),
                  let savedType = saved.sourceTypeRawValue,
                  let currentType = calendar.sourceTypeRawValue else { return false }
            return savedTitle == currentTitle && savedType == currentType
        }

        func recoverUniqueMatches(using matches: (CalendarCategoryLink, CalendarCategoryLink) -> Bool) {
            for (index, calendar) in inventory.enumerated() where assignments[index] == nil {
                let candidates = savedLinks.indices.filter { matches(savedLinks[$0], calendar) }
                guard candidates.count == 1,
                      let savedIndex = candidates.first,
                      !usedSavedIndices.contains(savedIndex) else { continue }
                let reverseMatches = inventory.indices.filter { matches(savedLinks[savedIndex], inventory[$0]) }
                guard reverseMatches.count == 1 else { continue }
                assignments[index] = savedIndex
                usedSavedIndices.insert(savedIndex)
            }
        }
        // A stable source ID distinguishes same-name accounts. Resolve those
        // stronger matches before considering source names or legacy titles.
        recoverUniqueMatches(using: sourceIdentifierMatches)
        recoverUniqueMatches(using: fallbackMatches)

        func refreshedLink(at index: Int) -> CalendarCategoryLink {
            // Inventory supplies the current identifier and metadata. Only
            // categoryId comes from the user's saved selection, including nil.
            var link = inventory[index]
            if let savedIndex = assignments[index] {
                link.categoryId = savedLinks[savedIndex].categoryId
            } else {
                link.categoryId = defaultCategory(link.calendarTitle)
            }
            return link
        }

        var activeLinks: [CalendarCategoryLink] = []
        var emittedIndices = Set<Int>()
        // Retain the order of calendars whose active IDs are still present.
        for link in previousLinks {
            guard let index = inventoryIndices[link.calendarIdentifier] else { continue }
            activeLinks.append(refreshedLink(at: index))
            emittedIndices.insert(index)
        }
        // Recovered, returning and new calendars follow inventory order.
        for index in inventory.indices where !emittedIndices.contains(index) {
            activeLinks.append(refreshedLink(at: index))
        }
        return Result(
            links: activeLinks,
            unavailableLinks: savedLinks.indices
                .filter { !usedSavedIndices.contains($0) }
                .map { savedLinks[$0] }
        )
    }

    private static func uniqueIdentifiers(in links: [CalendarCategoryLink]) -> [CalendarCategoryLink] {
        var seen = Set<String>()
        return links.filter { seen.insert($0.calendarIdentifier).inserted }
    }

    private static func hasSourceMetadata(_ link: CalendarCategoryLink) -> Bool {
        nonempty(link.sourceIdentifier) != nil || nonempty(link.sourceTitle) != nil ||
            link.sourceTypeRawValue != nil
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
