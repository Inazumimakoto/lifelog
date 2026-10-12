import SwiftUI

/// Color tokens used by app categories and schedule widgets.
enum AppColorPalette {
    static let defaultHex = "#F97316"

    // Ordered by hue for predictable scanning in swatch grids.
    static let presets: [String] = [
        "#EF4444", "#F97316", "#F59E0B", "#EAB308",
        "#84CC16", "#22C55E", "#10B981", "#14B8A6",
        "#06B6D4", "#0EA5E9", "#3B82F6", "#6366F1",
        "#8B5CF6", "#A855F7", "#D946EF", "#EC4899",
        "#F43F5E", "#A16207", "#78716C", "#94A3B8"
    ]

    static func color(for token: String) -> Color {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let color = Color(hex: trimmed) {
            return color
        }

        switch trimmed.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray", "grey": return .gray
        default: return .accentColor
        }
    }
}
