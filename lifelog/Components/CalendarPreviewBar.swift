import SwiftUI

/// The setting preview and both schedule grids share the same opaque canvas and chip colors.
struct CalendarGridSurface: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.self) private var environment

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Self.color(theme: theme, in: environment))
    }

    static func color(theme: AppTheme?, in environment: EnvironmentValues) -> Color {
        guard let theme, let scheme = theme.colorScheme else { return Color(uiColor: .systemBackground) }
        return blended(scheme == .dark ? .black : .white, over: theme.background,
                       opacity: scheme == .dark ? 0.55 : 0.70, in: environment)
    }

    /// Move only as far toward black or white as needed. Interpolating in linear sRGB
    /// also interpolates relative luminance, so this works on custom canvas and accent colors.
    static func selectionOutline(_ color: Color, on background: Color, in environment: EnvironmentValues) -> Color {
        let minimumRatio: Float = 3
        let canvas = AppTheme.luminance(background, in: environment)
        let ink = AppTheme.luminance(color, in: environment)
        let contrast = (max(canvas, ink) + 0.05) / (min(canvas, ink) + 0.05)
        guard contrast < minimumRatio else { return color }

        let towardWhite = 1.05 / (canvas + 0.05) > (canvas + 0.05) / 0.05
        // Leave headroom for rounding to the display's RGB values.
        let targetRatio = minimumRatio + 0.05
        let limit = towardWhite ? targetRatio * (canvas + 0.05) - 0.05 : (canvas + 0.05) / targetRatio - 0.05
        let endpoint: Float = towardWhite ? 1 : 0
        let fraction = min(1, max(0, (limit - ink) / (endpoint - ink)))
        let rgb = color.resolve(in: environment)
        func adjusted(_ channel: Float) -> Double { Double(channel + (endpoint - channel) * fraction) }
        return Color(.sRGBLinear,
                     red: adjusted(rgb.linearRed),
                     green: adjusted(rgb.linearGreen),
                     blue: adjusted(rgb.linearBlue))
    }

    /// Return the actual sRGB fill used to draw and measure contrast, including translucent categories.
    static func blended(_ color: Color, over canvas: Color, opacity: Double, in environment: EnvironmentValues) -> Color {
        let foreground = color.resolve(in: environment)
        let background = canvas.resolve(in: environment)
        let alpha = foreground.opacity * Float(opacity)
        let rgb = SIMD3(foreground.red, foreground.green, foreground.blue) * alpha
            + SIMD3(background.red, background.green, background.blue) * (1 - alpha)
        return Color(.sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }
}

struct CalendarPreviewBar: View {
    let title: String
    let color: Color
    let preferences: CalendarDisplayPreferences
    var continuesBefore = false
    var continuesAfter = false
    @Environment(\.appTheme) private var theme
    @Environment(\.self) private var environment

    var body: some View {
        let canvas = CalendarGridSurface.color(theme: theme, in: environment)
        let colors = Self.colors(category: color, opacity: preferences.opacity, canvas: canvas, in: environment)
        let leading: CGFloat = continuesBefore ? 0 : 4
        let trailing: CGFloat = continuesAfter ? 0 : 4
        CalendarPreviewText(text: title, fontSize: preferences.fontSize, textColor: UIColor(colors.text))
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: CalendarPreviewText.rowHeight(for: preferences.fontSize))
            .background {
                if preferences.opacity > 0 {
                    UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading,
                                           bottomTrailingRadius: trailing, topTrailingRadius: trailing)
                        .fill(colors.fill)
                }
            }
            .clipped()
    }

    static func colors(category: Color, opacity: Double, canvas: Color, in environment: EnvironmentValues) -> (fill: Color, text: Color) {
        let fill = CalendarGridSurface.blended(category, over: canvas, opacity: opacity, in: environment)
        let useBlack = AppTheme.prefersBlack(on: AppTheme.luminance(fill, in: environment))
        return (fill, useBlack ? .black : .white)
    }
}
