import SwiftUI
import XCTest
@testable import lifelify

@MainActor
final class CalendarGridAppearanceTests: XCTestCase {
    func testDisplayPreferences_preserveIndependentChoicesAndClampSavedValues() {
        let chosen = CalendarDisplayPreferences(fontSize: 13, opacity: 0.64)
        XCTAssertEqual(chosen.fontSize, 13)
        XCTAssertEqual(chosen.opacity, 0.64)
        let endpoints = CalendarDisplayPreferences(fontSize: 20, opacity: -0.1)
        XCTAssertEqual(endpoints.fontSize, 16)
        XCTAssertEqual(endpoints.opacity, 0)
        let opposite = CalendarDisplayPreferences(fontSize: -4, opacity: 2)
        XCTAssertEqual(opposite.fontSize, 8)
        XCTAssertEqual(opposite.opacity, 1)
        XCTAssertEqual(CalendarDisplayPreferences(fontSize: .nan, opacity: 1).fontSize, 11)
        XCTAssertEqual(CalendarDisplayPreferences(fontSize: 8, opacity: .infinity).opacity, 0.30)
    }

    func testEventRows_growToFitTheLargestSupportedFont() {
        let small = CalendarPreviewText.rowHeight(for: 8)
        let standard = CalendarPreviewText.rowHeight(for: 11)
        let large = CalendarPreviewText.rowHeight(for: 16)
        XCTAssertGreaterThan(standard, small)
        XCTAssertGreaterThan(large, standard)
        XCTAssertGreaterThanOrEqual(large, ceil(UIFont.systemFont(ofSize: 16, weight: .medium).lineHeight))
    }

    func testCalendarCell_keepsItsOriginalHeightAndReportsEventsThatDoNotFit() {
        XCTAssertEqual(CalendarGridMetrics.cellHeight, 88)
        let events = Array(1...6)
        for size in 8...16 {
            let metrics = CalendarGridMetrics(fontSize: CGFloat(size))
            XCTAssertGreaterThanOrEqual(metrics.laneCount, 2)
            XCTAssertLessThanOrEqual(metrics.laneCount, 4)
            let bottom = metrics.rowOffset(for: metrics.laneCount - 1) + metrics.rowHeight
            XCTAssertLessThanOrEqual(bottom, CalendarGridMetrics.cellHeight)

            let rows = CalendarPreviewLayout.rows(regularItems: events, itemLimit: metrics.laneCount, multiDayState: .empty)
            XCTAssertEqual(rows.last, .overflow(events.count - metrics.laneCount + 1))
        }
        XCTAssertGreaterThan(CalendarGridMetrics(fontSize: 8).laneCount, CalendarGridMetrics(fontSize: 16).laneCount)
    }

    func testBarOpacity_controlsTheFillAndTextUsesThatFillInBothAppearances() {
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            for (canvas, category) in [(Color.black, Color.white), (.white, .black)] {
                let transparent = CalendarPreviewBar.colors(category: category, opacity: 0, canvas: canvas, in: environment)
                let translucent = CalendarPreviewBar.colors(category: category, opacity: 0.30, canvas: canvas, in: environment)
                let opaque = CalendarPreviewBar.colors(category: category, opacity: 1, canvas: canvas, in: environment)
                XCTAssertEqual(transparent.fill.resolve(in: environment), canvas.resolve(in: environment))
                XCTAssertEqual(opaque.fill.resolve(in: environment), category.resolve(in: environment))
                let mixed = translucent.fill.resolve(in: environment)
                let expected = 0.7 * canvas.resolve(in: environment).red + 0.3 * category.resolve(in: environment).red
                XCTAssertEqual(mixed.red, expected, accuracy: 0.001)
                XCTAssertEqual(mixed.opacity, 1)
                let baseAlpha = CalendarPreviewBar.colors(category: category.opacity(0.5), opacity: 0.60, canvas: canvas, in: environment)
                XCTAssertEqual(baseAlpha.fill.resolve(in: environment).red, mixed.red, accuracy: 0.001)
                for colors in [transparent, translucent, opaque] {
                    let actualText = colors.text.resolve(in: environment)
                    XCTAssertTrue([Color.black, .white].map { $0.resolve(in: environment) }.contains(actualText))
                    XCTAssertGreaterThanOrEqual(contrast(colors.fill, colors.text, in: environment), 4.5)
                }
                XCTAssertNotEqual(transparent.text.resolve(in: environment), opaque.text.resolve(in: environment))
            }
        }
    }

    func testEveryPreset_keepsSmallTextLegibleWithAnyCategoryFillStrength() throws {
        let categories = ["#101010", "#FFFFFF", "#FF46E8", "#13E181", "#757575", "#767676"]
        for preset in AppTheme.Preset.allCases {
            let theme = try XCTUnwrap(AppTheme(selection: preset.selection))
            var environment = EnvironmentValues()
            environment.colorScheme = try XCTUnwrap(theme.colorScheme)
            let canvas = CalendarGridSurface.color(theme: theme, in: environment)
            XCTAssertEqual(canvas.resolve(in: environment).opacity, 1)
            for hex in categories {
                let category = try XCTUnwrap(Color(hex: hex))
                for alpha in [0.0, 0.3, 0.5, 1.0] {
                    let colors = CalendarPreviewBar.colors(category: category, opacity: alpha, canvas: canvas, in: environment)
                    XCTAssertGreaterThanOrEqual(contrast(colors.fill, colors.text, in: environment), 4.5,
                                                "\(preset), \(hex), \(alpha)")
                }
            }
        }
    }

    func testDayNumbers_useSecondaryForWeekendsAndOutsideDatesAndWhiteOverPhotos() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        func number(on day: Int, inMonth: Bool = true, overPhoto: Bool = false) throws -> CalendarDayNumber {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: day)))
            return CalendarDayNumber(date: date, calendar: calendar, isToday: true, isInMonth: inMonth,
                                     overPhoto: overPhoto, font: .subheadline)
        }
        XCTAssertEqual(try number(on: 13).textColor, Color.primary)
        XCTAssertEqual(try number(on: 14).textColor, Color.secondary)
        XCTAssertEqual(try number(on: 15).textColor, Color.secondary)
        XCTAssertEqual(try number(on: 13, inMonth: false).textColor, Color.secondary)
        XCTAssertEqual(try number(on: 14, overPhoto: true).textColor, Color.white)
    }

    private func contrast(_ lhs: Color, _ rhs: Color, in environment: EnvironmentValues) -> Float {
        let first = AppTheme.luminance(lhs, in: environment)
        let second = AppTheme.luminance(rhs, in: environment)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
