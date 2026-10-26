import Foundation

/// Optional web links shared by schedule records, editors and extensions (§4.2/4.3).
nonisolated enum ScheduleLink {
    static func url(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }) else { return nil }

        let hasScheme = value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
        let hostWithPort = value.range(of: #"^(?:[^/?#:@]+\.[^/?#:@]+|localhost):[0-9]+(?:[/?#]|$)"#,
                                       options: .regularExpression) != nil
        let candidate = hasScheme && !hostWithPort ? value : "https://" + value
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              host != ".", !host.hasPrefix("."), !host.hasSuffix(".."),
              components.port.map({ (1...65_535).contains($0) }) ?? true else { return nil }
        // A bare word is generally unfinished input; explicitly qualified URLs
        // may still target an intranet host. Domains, localhost and IPs work bare.
        if !hasScheme && !host.contains(".") && !host.contains(":") && host != "localhost" { return nil }
        components.scheme = scheme
        return components.url
    }

    static func normalizedString(from value: String?) -> String? {
        url(from: value)?.absoluteString
    }

    static func isValid(_ value: String?) -> Bool {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return url(from: value) != nil
    }
}
