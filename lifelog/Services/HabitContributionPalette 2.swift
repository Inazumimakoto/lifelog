import SwiftUI

/// Shared heatmap colors for the habit screens and widget.
enum HabitContributionPalette {
    static func colors(for scheme: ColorScheme) -> [Color] {
        scheme == .dark ? darkColors : lightColors
    }

    private static let darkColors: [Color] = [
        Color(hex: "#161b22") ?? Color(red: 0.09, green: 0.11, blue: 0.13),
        Color(hex: "#0e4429") ?? Color(red: 0.05, green: 0.27, blue: 0.16),
        Color(hex: "#006d32") ?? Color(red: 0.00, green: 0.43, blue: 0.20),
        Color(hex: "#26a641") ?? Color(red: 0.15, green: 0.65, blue: 0.25),
        Color(hex: "#39d353") ?? Color(red: 0.22, green: 0.83, blue: 0.33)
    ]

    private static let lightColors: [Color] = [
        Color(hex: "#ebedf0") ?? Color(red: 0.92, green: 0.93, blue: 0.94),
        Color(hex: "#9be9a8") ?? Color(red: 0.61, green: 0.91, blue: 0.66),
        Color(hex: "#40c463") ?? Color(red: 0.25, green: 0.77, blue: 0.39),
        Color(hex: "#30a14e") ?? Color(red: 0.19, green: 0.63, blue: 0.31),
        Color(hex: "#216e39") ?? Color(red: 0.13, green: 0.43, blue: 0.22)
    ]
}
