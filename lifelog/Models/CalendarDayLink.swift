import Foundation

/// Shared by the schedule widget and app; see docs/requirements.md for widget date navigation.
enum CalendarDayLink {
    /// Keep the URL Gregorian and locale independent even when the visible calendar is localized.
    nonisolated static func url(for date: Date, timeZone: TimeZone = .current) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents()
        components.scheme = "lifelog"
        components.host = "calendar"
        components.queryItems = [URLQueryItem(name: "date", value: formatter.string(from: date))]
        return components.url!
    }

    /// A day is interpreted in the device time zone, so it cannot shift through a UTC conversion.
    nonisolated static func date(from url: URL, timeZone: TimeZone = .current) -> Date? {
        guard url.scheme?.lowercased() == "lifelog",
              url.host?.lowercased() == "calendar" || url.path.lowercased() == "/calendar",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "date" })?.value else {
            return nil
        }

        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }) else { return nil }

        let parts = value.split(separator: "-")
        guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dateComponents = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: dateComponents) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }
}
