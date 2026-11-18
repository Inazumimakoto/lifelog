import Foundation

/// Appearance of event and task bars in the app and its wallpaper calendar.
struct CalendarDisplayPreferences: Equatable {
    static let fontSizeKey = "calendar.grid.eventFontSize"
    static let opacityKey = "calendar.grid.categoryFillOpacity"
    static let fontSizeRange = 8.0...16.0
    static let opacityRange = 0.0...1.0
    static let defaultFontSize = 11.0
    static let defaultOpacity = 0.30

    let fontSize: CGFloat
    let opacity: Double

    init(defaults: UserDefaults = .standard) {
        self.init(fontSize: defaults.object(forKey: Self.fontSizeKey) as? Double ?? Self.defaultFontSize,
                  opacity: defaults.object(forKey: Self.opacityKey) as? Double ?? Self.defaultOpacity)
    }

    init(fontSize: Double, opacity: Double) {
        let size = fontSize.isFinite ? fontSize : Self.defaultFontSize
        let alpha = opacity.isFinite ? opacity : Self.defaultOpacity
        self.fontSize = CGFloat(min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound))
        self.opacity = min(max(alpha, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
    }
}
