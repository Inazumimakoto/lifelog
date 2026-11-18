import SwiftUI
import XCTest
@testable import lifelify

@MainActor
final class AppIconPaletteTests: XCTestCase {
    func testPresets_useTheirExactAlternateInEitherSystemAppearance() {
        let examples: [(AppTheme.Preset, AppIconPalette)] = [
            (.whiteBlue, .whiteBlue), (.blackBlue, .blackBlue), (.mint, .mint), (.sky, .sky),
            (.lavender, .lavender), (.rose, .rose), (.forest, .forest), (.midnight, .midnight)
        ]
        XCTAssertEqual(Set(examples.map(\.0)), Set(AppTheme.Preset.allCases))
        for (preset, expected) in examples {
            for scheme in [ColorScheme.light, .dark] {
                let icon = AppIconPalette.resolve(selection: preset.selection, followsTheme: true, systemColorScheme: scheme)
                XCTAssertEqual(icon, expected, "\(preset), \(scheme)")
                XCTAssertNotNil(icon.alternateName)
                XCTAssertEqual(icon.backgroundHex, preset.selection.backgroundHex)
                XCTAssertEqual(icon.accentHex, preset.selection.accentHex)
            }
        }
    }

    func testSystemThemeOrDisabledIconMatching_returnsTheOriginalIconInDeviceAppearance() {
        for (scheme, original) in [(ColorScheme.light, AppIconPalette.primaryLight), (.dark, .primaryDark)] {
            let system = AppIconPalette.resolve(selection: .system, followsTheme: true, systemColorScheme: scheme)
            let disabled = AppIconPalette.resolve(selection: AppTheme.Preset.forest.selection, followsTheme: false, systemColorScheme: scheme)
            XCTAssertEqual(system, original)
            XCTAssertEqual(disabled, original)
            XCTAssertNil(original.alternateName)
        }
    }

    func testCustomColors_selectTheNearestBackgroundAndAccentIndependently() {
        // Each input is deliberately just off a bundled color.
        let examples = [
            ("#FFE8AF", "#E53D65", "#FFE7AD", "#E63C66"),
            ("#FFE8AF", "#29C8CC", "#FFE7AD", "#29C7CD"),
            ("#613C25", "#29C8CC", "#613D24", "#29C7CD")
        ]
        for (background, accent, expectedBackground, expectedAccent) in examples {
            let selection = AppTheme.Selection(backgroundHex: background, accentHex: accent)
            let icon = AppIconPalette.resolve(selection: selection, followsTheme: true, systemColorScheme: .light)
            XCTAssertEqual(icon.backgroundHex, expectedBackground)
            XCTAssertEqual(icon.accentHex, expectedAccent)
            XCTAssertNotNil(icon.alternateName)
        }
    }

    func testAccentOnlySelection_keepsTheAccentWhenDeviceAppearanceChanges() {
        let selection = AppTheme.Selection(backgroundHex: "", accentHex: "#E63C66")
        for (scheme, background) in [(ColorScheme.light, "#FFFFFF"), (.dark, "#000000")] {
            let icon = AppIconPalette.resolve(selection: selection, followsTheme: true, systemColorScheme: scheme)
            XCTAssertEqual(icon.backgroundHex, background)
            XCTAssertEqual(icon.accentHex, selection.accentHex)
        }
    }

    func testLegacyWhiteAndBlack_keepTheSystemAccent() {
        for color in ["#FFFFFF", "#000000"] {
            let restored = AppTheme.Selection(storedValue: nil, legacyBackground: color)
            XCTAssertEqual(restored.backgroundHex, color)
            XCTAssertEqual(restored.accentHex, "")
        }
    }

    func testAllSelectableAlternates_areDeclaredInTheBuiltApp() throws {
        let iconInfo = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let registered = try XCTUnwrap(iconInfo["CFBundleAlternateIcons"] as? [String: Any])
        let names = try AppIconPalette.alternates.map { try XCTUnwrap($0.alternateName) }
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(Set(names).subtracting(registered.keys), [], "Icon names missing from the host app's Info.plist")
    }
}
