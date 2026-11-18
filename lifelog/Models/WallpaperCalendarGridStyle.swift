import SwiftUI
import UIKit

/// The preview and exported wallpaper fit their event lanes inside the same fixed-size day cells.
struct WallpaperCalendarGridStyle {
    static let cellHeight: CGFloat = 88
    static let topPadding: CGFloat = 4
    static let dateHeight: CGFloat = 18
    static let rowSpacing: CGFloat = 2
    static let todayColor = Color(uiColor: .systemBlue)
    static let todayOpacity = 0.28

    let preferences: CalendarDisplayPreferences
    let font: UIFont
    let rowHeight: CGFloat
    let itemLimit: Int

    init(preferences: CalendarDisplayPreferences) {
        self.preferences = preferences
        font = .systemFont(ofSize: preferences.fontSize, weight: .medium, width: .condensed)
        rowHeight = max(14, ceil(font.lineHeight))
        let available = Self.cellHeight - Self.topPadding - Self.dateHeight
        itemLimit = min(4, Int(available / (rowHeight + Self.rowSpacing)))
    }

    func rowOffset(_ index: Int) -> CGFloat {
        Self.topPadding + Self.dateHeight + Self.rowSpacing + CGFloat(index) * (rowHeight + Self.rowSpacing)
    }

    func title(for segment: WallpaperCalendarWeekMultiDaySegment, privacyMode: WallpaperCalendarPrivacyMode) -> String {
        segment.continuesBeforeWeek && preferences.opacity > 0 ? " " : segment.displayTitle(privacyMode: privacyMode)
    }

    func attributedTitle(_ title: String, category: Color, settings: WallpaperCalendarSettings,
                         hasPhoto: Bool, isToday: Bool) -> NSAttributedString {
        var environment = EnvironmentValues()
        environment.colorScheme = hasPhoto || WallpaperCalendarBackgroundPalette.isDark(settings.backgroundColorToken) ? .dark : .light
        var canvas: Color = hasPhoto ? .black : AppColorPalette.color(for: settings.backgroundColorToken)
        if isToday {
            canvas = CalendarGridSurface.blended(Self.todayColor, over: canvas, opacity: Self.todayOpacity, in: environment)
        }
        let ink = CalendarPreviewBar.colors(category: category, opacity: preferences.opacity,
                                           canvas: canvas, in: environment).text
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(ink)]
        let fillOpacity = Double(category.resolve(in: environment).opacity) * preferences.opacity
        if hasPhoto && fillOpacity < 1 {
            // Keep the face of small characters intact even on a busy photo.
            let shadowColor: UIColor = ink == .black ? .white : .black
            attributes[.shadow] = Self.textShadow(color: shadowColor.withAlphaComponent(0.50 * (1 - fillOpacity)))
        }
        return NSAttributedString(string: title, attributes: attributes)
    }

    static func textShadow(color: UIColor) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowBlurRadius = 1.2
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        return shadow
    }
}
