//
//  ReviewLocationModels.swift
//  lifelog
//

import Foundation
import MapKit

// MARK: - Review Map

struct ReviewLocationEntry: Identifiable, Hashable {
    let id: String
    let date: Date
    let location: DiaryLocation
    let photoPaths: [String]
    let tags: [String]

    init(date: Date, location: DiaryLocation, photoPaths: [String], tags: [String]) {
        self.date = date
        self.location = location
        self.photoPaths = photoPaths
        self.tags = tags
        self.id = "\(date.timeIntervalSince1970)-\(location.id.uuidString)"
    }
}

struct ReviewLocationVisit: Identifiable, Hashable {
    let id: String
    let date: Date
    let photoPaths: [String]
    let tags: [String]

    init(date: Date, photoPaths: [String], tags: [String]) {
        let normalized = date.startOfDay
        self.date = normalized
        self.photoPaths = photoPaths
        self.tags = tags
        self.id = "\(normalized.timeIntervalSince1970)"
    }
}

struct ReviewLocationGroup: Identifiable, Hashable {
    let id: String
    let location: DiaryLocation
    let visits: [ReviewLocationVisit]

    var name: String { location.name }
    var address: String? { location.address }
    var coordinate: CLLocationCoordinate2D { location.coordinate }
    var uniqueDates: [Date] {
        visits.map(\.date)
    }
    var allTags: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for tag in visits.flatMap(\.tags) {
            let key = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            ordered.append(tag)
        }
        return ordered
    }
    var count: Int { uniqueDates.count }
    var latestDate: Date { uniqueDates.first ?? Date.distantPast }
    var dateSummary: String {
        ReviewDateFormatter.summary(for: uniqueDates)
    }
}

struct ReviewLocationGroupBuilder {
    let id: String
    let location: DiaryLocation
    var visitSnapshots: [Date: ReviewLocationVisitSnapshot]

    init(location: DiaryLocation, date: Date, photoPaths: [String], tags: [String]) {
        self.location = location
        self.id = Self.makeKey(for: location)
        self.visitSnapshots = [:]
        add(date: date, photoPaths: photoPaths, tags: tags)
    }

    static func makeKey(for location: DiaryLocation) -> String {
        if let mapItemURL = location.mapItemURL, mapItemURL.isEmpty == false {
            return "mapitem:\(mapItemURL)"
        }
        let lat = (location.latitude * 10_000).rounded() / 10_000
        let lon = (location.longitude * 10_000).rounded() / 10_000
        return "coord:\(lat),\(lon)"
    }

    mutating func add(date: Date, photoPaths: [String], tags: [String]) {
        let keyDate = date.startOfDay
        if var existing = visitSnapshots[keyDate] {
            for path in photoPaths where existing.photoPaths.contains(path) == false {
                existing.photoPaths.append(path)
            }
            for tag in tags where existing.containsTag(tag) == false {
                existing.tags.append(tag)
            }
            visitSnapshots[keyDate] = existing
        } else {
            visitSnapshots[keyDate] = ReviewLocationVisitSnapshot(photoPaths: photoPaths, tags: tags)
        }
    }

    var visits: [ReviewLocationVisit] {
        visitSnapshots
            .map { ReviewLocationVisit(date: $0.key, photoPaths: $0.value.photoPaths, tags: $0.value.tags) }
            .sorted { $0.date > $1.date }
    }
}

struct ReviewLocationVisitSnapshot: Hashable {
    var photoPaths: [String]
    var tags: [String]

    func containsTag(_ tag: String) -> Bool {
        let key = tagKey(tag)
        return tags.contains { tagKey($0) == key }
    }

    private func tagKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum ReviewDateFormatter {
    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    static func summary(for dates: [Date]) -> String {
        guard let first = dates.first else { return "" }
        if dates.count == 1 {
            return monthDay.string(from: first)
        }
        let calendar = Calendar.current
        let sameMonth = dates.allSatisfy { calendar.isDate($0, equalTo: first, toGranularity: .month) }
        if sameMonth {
            let dayNumbers = dates.dropFirst().map { String(calendar.component(.day, from: $0)) }
            if dates.count <= 3 {
                return ([monthDay.string(from: first)] + Array(dayNumbers.prefix(2))).joined(separator: ",")
            }
            let shown = [monthDay.string(from: first)] + Array(dayNumbers.prefix(2))
            return shown.joined(separator: ",") + "+\(dates.count - 3)"
        }
        if dates.count == 2 {
            return dates.map { monthDay.string(from: $0) }.joined(separator: ",")
        }
        let shown = dates.prefix(2).map { monthDay.string(from: $0) }
        return shown.joined(separator: ",") + "+\(dates.count - 2)"
    }
}
