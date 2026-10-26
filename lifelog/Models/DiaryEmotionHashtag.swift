import Foundation

/// Match complete hashtag tokens while preserving surrounding formatting.
nonisolated enum DiaryEmotionHashtag {
    private static let whitespace = "[\\u0009-\\u000D\\u0020\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]"
    private static func expression(_ hashTag: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: "(^|" + whitespace + ")" + NSRegularExpression.escapedPattern(for: hashTag) + "(?=$|" + whitespace + ")")
    }
    static func contains(_ hashTag: String, in text: String) -> Bool { expression(hashTag)?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
    static func toggling(_ hashTag: String, in text: String) -> String {
        guard !hashTag.isEmpty, let expression = expression(hashTag) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        if expression.firstMatch(in: text, range: range) != nil { return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "$1") }
        let hasTrailingWhitespace = text.range(of: whitespace + "$", options: .regularExpression) != nil
        return text + (text.isEmpty || hasTrailingWhitespace ? "" : " ") + hashTag
    }
}
