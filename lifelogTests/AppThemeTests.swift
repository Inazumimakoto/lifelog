import SwiftUI
import XCTest
@testable import lifelify

@MainActor
final class AppThemeTests: XCTestCase {
    func testBackgroundContrast_selectsTheMoreLegibleSystemAppearance() {
        let examples: [(String, ColorScheme)] = [
            ("#000000", .dark), ("#19263B", .dark), ("#0000FF", .dark),
            ("#00FF00", .light), ("#FFFFFF", .light),
            // Adjacent grays straddle the point where black overtakes white.
            ("#757575", .dark), ("#767676", .light)
        ]
        for (hex, expected) in examples {
            let theme = AppTheme(selection: .init(backgroundHex: hex, accentHex: "#006699"))
            XCTAssertEqual(theme?.colorScheme, expected, hex)
        }
    }

    func testStoredSelection_roundTripsBothColorsTogether() throws {
        let original = AppTheme.Selection(backgroundHex: "#00FF80", accentHex: "#491DCF")
        let restored = AppTheme.Selection(storedValue: original.storedValue, legacyBackground: "#19263B")

        XCTAssertEqual(restored.backgroundHex, original.backgroundHex)
        XCTAssertEqual(restored.accentHex, original.accentHex)
        let theme = try XCTUnwrap(AppTheme(selection: restored))
        XCTAssertEqual(AppTheme.hex(from: theme.background), original.backgroundHex)
        let accent = try XCTUnwrap(theme.accent)
        XCTAssertEqual(AppTheme.hex(from: accent), original.accentHex)
    }

    func testPresets_restoreContrastingColorsAndUseTheirAccentForSelection() throws {
        for preset in AppTheme.Preset.allCases {
            let selection = preset.selection
            XCTAssertFalse(selection.backgroundHex.isEmpty)
            XCTAssertFalse(selection.accentHex.isEmpty)
            XCTAssertNotEqual(selection.backgroundHex, selection.accentHex)
            let restored = AppTheme.Selection(storedValue: selection.storedValue, legacyBackground: "")
            XCTAssertEqual(restored, selection)
            let theme = try XCTUnwrap(AppTheme(selection: restored))
            let accent = try XCTUnwrap(theme.accent)
            let scheme = try XCTUnwrap(theme.colorScheme)
            XCTAssertGreaterThanOrEqual(contrast(accent, theme.background, scheme: scheme), 4.5, "\(preset)")
            XCTAssertEqual(theme.selectionIndicator, accent, "\(preset)")
        }
    }

    func testLegacyPresets_restoreTheMatchingBackgroundAndAccent() {
        let legacyPresets: [(String, AppTheme.Preset)] = [
            ("#CFE9D8", .mint), ("#CDE4F5", .sky), ("#E2DCF4", .lavender),
            ("#F4D9DE", .rose), ("#174B39", .forest), ("#19263B", .midnight)
        ]
        for (hex, preset) in legacyPresets {
            let restored = AppTheme.Selection(storedValue: nil, legacyBackground: hex.lowercased())
            XCTAssertEqual(restored, preset.selection)
        }
    }

    func testLegacyCustomBackground_keepsItsColorAndSystemAccent() {
        let restored = AppTheme.Selection(storedValue: nil, legacyBackground: "#607052")
        XCTAssertEqual(restored.backgroundHex, "#607052")
        XCTAssertEqual(restored.accentHex, "")
    }

    func testAccentOnlySelection_preservesSystemBackgroundAndAppearance() throws {
        let selected = AppTheme.Selection(backgroundHex: "", accentHex: "#832564")
        let restored = AppTheme.Selection(storedValue: selected.storedValue, legacyBackground: "#CFE9D8")
        XCTAssertEqual(restored, selected)
        for scheme in [ColorScheme.light, .dark] {
            let theme = try XCTUnwrap(AppTheme(selection: restored, systemColorScheme: scheme))
            XCTAssertNil(theme.colorScheme)
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            XCTAssertEqual(theme.background.resolve(in: environment),
                           Color(uiColor: .systemBackground).resolve(in: environment))
        }
    }

    func testSystemSelection_takesPrecedenceOverLegacyColorAfterReset() {
        let restored = AppTheme.Selection(
            storedValue: AppTheme.Selection.system.storedValue,
            legacyBackground: "#607052"
        )
        XCTAssertEqual(restored, .system)
        XCTAssertNil(AppTheme(selection: restored))
    }

    func testDefaultAndInvalidLegacyValues_followTheSystemAppearance() {
        for hex in ["", "unknown", "#12", "#12345678"] {
            let restored = AppTheme.Selection(storedValue: nil, legacyBackground: hex)
            XCTAssertEqual(restored, .system, hex)
            XCTAssertNil(AppTheme(selection: restored), hex)
        }
    }

    func testAccentForegroundContrast_isReadableOnLightAndDarkButtons() throws {
        // Use a screen background opposite to the button to catch an accidental
        // choice of text color based on the screen instead of the button.
        for (background, accent) in [("#000000", "#FFFF00"), ("#FFFFFF", "#101020")] {
            let selection = AppTheme.Selection(backgroundHex: background, accentHex: accent)
            let theme = try XCTUnwrap(AppTheme(selection: selection))
            let fill = try XCTUnwrap(Color(hex: accent))
            let scheme = try XCTUnwrap(theme.colorScheme)
            XCTAssertGreaterThanOrEqual(contrast(theme.onAccent, fill, scheme: scheme), 4.5)
        }
    }

    func testCalendarSelectionIndicator_standsOutWhenBackgroundMatchesAccent() throws {
        for hex in ["#F8FFC0", "#08361B", "#007AFF"] {
            let theme = try XCTUnwrap(AppTheme(selection: .init(backgroundHex: hex, accentHex: hex)))
            let scheme = try XCTUnwrap(theme.colorScheme)
            XCTAssertGreaterThanOrEqual(contrast(theme.selectionIndicator, theme.background, scheme: scheme), 3)
        }
    }

    private func contrast(_ foreground: Color, _ background: Color, scheme: ColorScheme) -> Float {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        func luminance(_ color: Color) -> Float {
            let rgb = color.resolve(in: environment)
            return 0.2126 * rgb.linearRed + 0.7152 * rgb.linearGreen + 0.0722 * rgb.linearBlue
        }
        let a = luminance(foreground)
        let b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func testPickerColor_convertsToSRGBAndClampsOutOfGamutChannels() {
        let linearRed = Color(.sRGBLinear, red: 0.5, green: 0, blue: 0)
        XCTAssertEqual(AppTheme.hex(from: linearRed), "#BC0000")

        let extended = Color(.sRGB, red: 1.25, green: -0.25, blue: 0.25)
        XCTAssertEqual(AppTheme.hex(from: extended), "#FF0040")
    }
}
