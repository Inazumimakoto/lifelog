import SwiftUI
import UIKit
import XCTest
@testable import lifelify

@MainActor
final class WallpaperCalendarPhotoBackgroundTests: XCTestCase {
    private let canvasSize = CGSize(width: 160, height: 320)

    func testPhotoEventTitles_preserveGlyphsInPreviewAndJPEG() throws {
        let size = CGSize(width: 390, height: 600)
        let scale: CGFloat = 3
        // Exercise both an invisible multi-day fill on a bright photo and the default
        // category opacity on a darker photo, at the normal lock-screen text size.
        for (background, opacity) in [(UIColor.white, 0.0), (UIColor.darkGray, 0.30)] {
            let photo = makeImage(size: size) { rect in
                background.setFill()
                UIRectFill(rect)
            }
            let style = WallpaperCalendarGridStyle(preferences: CalendarDisplayPreferences(fontSize: 11, opacity: opacity))
            let snapshot = eventSnapshot(style: style, category: .red, continuesBeforeWeek: opacity == 0)
            let (previewImage, jpeg) = try eventImages(snapshot: snapshot, photo: photo, size: size, scale: scale)
            let rowTop = size.height * 0.36 + 24 + 4 + style.rowOffset(0)
            let margin = size.width * 0.07
            let cellWidth = (size.width - margin * 2 - 6 * 4) / 7
            for (name, image) in [("Preview", previewImage), ("JPEG", jpeg)] {
                let rowRect = CGRect(x: 0, y: floor(rowTop * scale), width: size.width * scale,
                                     height: ceil(style.rowHeight * scale))
                let strip = try XCTUnwrap(image.cgImage?.cropping(to: rowRect))
                attach(UIImage(cgImage: strip), name: "\(name)-event-row-\(Int(opacity * 100))")
                let pixels = try PixelBuffer(UIImage(cgImage: strip))
                let backdrop = pixels.color(x: 2, y: 2)
                if opacity == 0 {
                    // Near the end of the two-column bar the bright photo should show through.
                    XCTAssertGreaterThan(backdrop.red, 0.7)
                    assertColor(pixels.color(x: Int((margin + cellWidth * 1.8) * scale), y: 5), equals: backdrop)
                }
                for (column, title, width) in [(0, "予定B8", cellWidth * 2 + 4), (3, "会議", cellWidth)] {
                    let left = Int((margin + CGFloat(column) * (cellWidth + 4)) * scale)
                    let right = left + Int(width * scale)
                    let reference = makeImage(size: CGSize(width: width, height: style.rowHeight), scale: scale) { rect in
                        UIColor.black.setFill()
                        UIRectFill(rect)
                        (title as NSString).draw(at: .zero, withAttributes: [.font: style.font, .foregroundColor: UIColor.white])
                    }
                    let unstyled = try PixelBuffer(reference)
                    var referenceFace = 0
                    for y in 0..<unstyled.height {
                        for x in 0..<unstyled.width where unstyled.color(x: x, y: y).green > 0.90 { referenceFace += 1 }
                    }
                    var face = 0
                    var darkEdge = 0
                    var darkest = 1.0
                    for y in 0..<pixels.height {
                        for x in left..<right {
                            let green = pixels.color(x: x, y: y).green
                            if green > 0.90 { face += 1 }
                            if green < 0.25 { darkEdge += 1 }
                            darkest = min(darkest, green)
                        }
                    }
                    let context = "\(name), \(title), category opacity \(opacity)"
                    XCTAssertGreaterThan(referenceFace, 30, context)
                    // Compare the face of each glyph to the actual undecorated font.
                    // A thick black stroke can make a row darker while erasing its characters.
                    XCTAssertGreaterThan(Double(face), Double(referenceFace) * 0.55, context)
                    XCTAssertLessThan(Double(face), Double(referenceFace) * 1.6, context)
                    if opacity == 0 {
                        XCTAssertLessThan(darkest, backdrop.green - 0.08, "\(context) needs an edge visible on a bright photo")
                        XCTAssertLessThan(darkEdge, referenceFace, "\(context) shadow should not outweigh the glyphs")
                    }
                }
            }
        }
    }

    func testCategoryFill_matchesSelectedOpacityInPreviewAndJPEG() throws {
        let size = CGSize(width: 390, height: 600)
        let scale: CGFloat = 3
        let photo = makeImage(size: size) { rect in
            UIColor.darkGray.setFill()
            UIRectFill(rect)
        }
        let category = Color(.sRGB, red: 1, green: 0, blue: 0)
        let percentages = [0, 30, 50, 60, 62, 100]
        let margin = size.width * 0.07
        let cellWidth = (size.width - 2 * margin - 6 * 4) / 7
        // Solid interiors between the label and the trailing corner. No text, shadow, or antialiasing.
        let positions = [("single", margin + 3 * (cellWidth + 4) + cellWidth - 8),
                         ("multi-day", margin + cellWidth * 1.7)]
        var report: [String] = []
        for (background, image) in [("photo", Optional(photo)), ("solid", nil)] {
            var samples: [String: [Double]] = [:]
            for percent in percentages {
                let style = WallpaperCalendarGridStyle(preferences: .init(fontSize: 11, opacity: Double(percent) / 100))
                let snapshot = eventSnapshot(style: style, category: category)
                let (preview, jpeg) = try eventImages(snapshot: snapshot, photo: image, size: size, scale: scale)
                let rowTop = size.height * 0.36 + 24 + 4 + style.rowOffset(0)
                let centerY = Int((rowTop + style.rowHeight / 2) * scale)
                for (output, frame) in [("Preview", preview), ("JPEG", jpeg)] {
                    let pixels = try PixelBuffer(frame)
                    for (kind, pointX) in positions {
                        let x = Int(pointX * scale)
                        let sample = pixels.color(x: x, y: centerY)
                        if percent == 0 {
                            assertColor(sample, equals: pixels.color(x: 2, y: centerY))
                        } else if percent == 100 {
                            assertColor(sample, equals: .red)
                        }
                        samples["\(output) \(kind)", default: []].append(sample.red)
                    }
                    if background == "photo" && output == "JPEG" && [30, 62].contains(percent) {
                        let rect = CGRect(x: margin * scale - 5, y: floor(rowTop * scale - 5),
                                          width: (4 * cellWidth + 12) * scale + 10, height: ceil(style.rowHeight * scale) + 10)
                        let strip = try XCTUnwrap(frame.cgImage?.cropping(to: rect))
                        attach(UIImage(cgImage: strip), name: "Photo-JPEG-category-fill-\(percent)")
                    }
                }
            }
            for (label, values) in samples.sorted(by: { $0.key < $1.key }) {
                let clear = try XCTUnwrap(values.first)
                let filled = try XCTUnwrap(values.last)
                XCTAssertGreaterThan(filled - clear, 0.50, "The red test bar must contrast with its background")
                for (percent, red) in zip(percentages, values) {
                    let effectivePercent = 100 * (red - clear) / (filled - clear)
                    XCTAssertEqual(effectivePercent, Double(percent), accuracy: 2, "\(background) \(label) at \(percent)%")
                    report.append(String(format: "%@ %@ | %d%% -> %.2f%%", background, label, percent, effectivePercent))
                }
            }
        }
        let measurement = XCTAttachment(string: report.joined(separator: "\n"))
        measurement.name = "Measured category fill percentages"
        measurement.lifetime = .keepAlways
        add(measurement)
    }

    func testDisplayChanges_updatePreviewAndInvalidateCachedWallpaper() throws {
        let suite = "WallpaperDisplayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let fileManager = IsolatedFileManager(rootURL: directory)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? fileManager.removeItem(at: directory)
        }
        let store = WallpaperCalendarSettingsStore(defaults: defaults, fileManager: fileManager)
        let renderer = WallpaperCalendarRenderer(settingsStore: store,
                                                 dataProvider: WallpaperCalendarDataProvider(displayDefaults: defaults),
                                                 fileManager: fileManager)
        let now = Date(timeIntervalSince1970: 946_684_800)
        func renderAndReadFingerprint() throws -> String {
            _ = try renderer.render(now: now, screenSize: canvasSize, scale: 1)
            return try XCTUnwrap(store.load().lastGeneratedFingerprint)
        }
        func previewStyle() -> WallpaperCalendarGridStyle {
            renderer.makePreviewSnapshot(settings: store.load(), now: now).gridStyle
        }

        let original = try renderAndReadFingerprint()
        XCTAssertEqual(previewStyle().font.pointSize, CalendarDisplayPreferences.defaultFontSize)
        XCTAssertEqual(previewStyle().preferences.opacity, CalendarDisplayPreferences.defaultOpacity)
        XCTAssertEqual(previewStyle().itemLimit, 4)

        defaults.set(0.0, forKey: CalendarDisplayPreferences.opacityKey)
        let transparent = try renderAndReadFingerprint()
        XCTAssertNotEqual(transparent, original)
        XCTAssertEqual(previewStyle().preferences.opacity, 0)

        defaults.set(16.0, forKey: CalendarDisplayPreferences.fontSizeKey)
        let enlarged = try renderAndReadFingerprint()
        XCTAssertNotEqual(enlarged, transparent)
        let large = previewStyle()
        XCTAssertEqual(large.font.pointSize, 16)
        XCTAssertLessThan(large.itemLimit, 4)
        XCTAssertGreaterThanOrEqual(large.rowHeight, large.font.lineHeight)
        XCTAssertLessThanOrEqual(large.rowOffset(large.itemLimit - 1) + large.rowHeight, 88)
        XCTAssertEqual(try renderAndReadFingerprint(), enlarged)

        defaults.removeObject(forKey: CalendarDisplayPreferences.fontSizeKey)
        defaults.removeObject(forKey: CalendarDisplayPreferences.opacityKey)
        XCTAssertEqual(try renderAndReadFingerprint(), original)
    }

    func testZoomedOutLandscapePhoto_extendsEdgesWithoutRepeatingCenterSubject() throws {
        let source = landscapePhoto()
        let output = render(source, adjustment: fittedAdjustment(for: source))
        let pixels = try PixelBuffer(output)

        // Blur can mix adjacent colors, but each margin must retain its own edge's color.
        assertDominantEdgeColor(pixels.color(x: 80, y: 12), channel: .red)
        assertDominantEdgeColor(pixels.color(x: 80, y: 86), channel: .red)
        assertDominantEdgeColor(pixels.color(x: 80, y: 236), channel: .blue)
        assertDominantEdgeColor(pixels.color(x: 80, y: 307), channel: .blue)
        assertColor(pixels.color(x: 80, y: 160), equals: .magenta)
        assertColor(pixels.color(x: 50, y: 160), equals: .green)
        assertOpaque(pixels)
        attach(output, name: "Landscape photo fitted with extended edges")
    }

    func testZoomedOutPortraitPhoto_fillsBothSideMarginsWithTheirRespectiveEdges() throws {
        let source = makeImage(size: CGSize(width: 40, height: 160)) { rect in
            UIColor.green.setFill()
            UIRectFill(rect)
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 10, height: 160))
            UIColor.blue.setFill()
            UIRectFill(CGRect(x: 30, y: 0, width: 10, height: 160))
            UIColor.magenta.setFill()
            UIRectFill(CGRect(x: 15, y: 60, width: 10, height: 40))
        }
        let output = render(source, adjustment: fittedAdjustment(for: source))
        let pixels = try PixelBuffer(output)

        assertDominantEdgeColor(pixels.color(x: 8, y: 160), channel: .red)
        assertDominantEdgeColor(pixels.color(x: 151, y: 160), channel: .blue)
        assertColor(pixels.color(x: 80, y: 160), equals: .magenta)
        assertOpaque(pixels)
        attach(output, name: "Portrait photo fitted with extended sides")
    }

    func testDraggingExistingComposition_movesSharpPhotoAndItsEdgeFillTogether() throws {
        let source = landscapePhoto()
        let background = WallpaperCalendarPhotoBackground(image: source)
        var adjustment = fittedAdjustment(for: source)
        background.update(size: canvasSize, adjustment: adjustment, contentsScale: 1)
        let before = try PixelBuffer(renderLayer(background.layer, size: canvasSize))

        adjustment.offsetX = 0.15
        adjustment.offsetY = 0.05
        background.update(size: canvasSize, adjustment: adjustment, contentsScale: 1)
        let output = renderLayer(background.layer, size: canvasSize)
        let after = try PixelBuffer(output)

        assertColor(before.color(x: 80, y: 166), equals: .magenta)
        assertColor(after.color(x: 80, y: 166), equals: .green)
        assertColor(after.color(x: 104, y: 176), equals: .magenta)
        assertDominantEdgeColor(after.color(x: 104, y: 20), channel: .red)
        assertDominantEdgeColor(after.color(x: 104, y: 300), channel: .blue)
        assertOpaque(after)
        attach(output, name: "Fitted photo after horizontal and vertical drag")
    }

    func testCoveringPhoto_preservesOriginalPixelsIncludingItsEdges() throws {
        let source = landscapePhoto()
        let output = render(source, adjustment: .defaultValue, size: source.size)
        let actual = try PixelBuffer(output)
        let expected = try PixelBuffer(source)

        for y in stride(from: 0, to: actual.height, by: 3) {
            for x in stride(from: 0, to: actual.width, by: 3) {
                assertColor(actual.color(x: x, y: y), equals: expected.color(x: x, y: y), tolerance: 0.015)
            }
        }
    }

    func testReturningFromFitToCover_removesEdgeFeatherFromOriginalPhoto() throws {
        let source = landscapePhoto()
        let background = WallpaperCalendarPhotoBackground(image: source)
        background.update(size: canvasSize, adjustment: fittedAdjustment(for: source), contentsScale: 1)
        background.update(size: source.size, adjustment: .defaultValue, contentsScale: 1)
        let actual = try PixelBuffer(renderLayer(background.layer, size: source.size))
        let expected = try PixelBuffer(source)

        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 80, y: 0), CGPoint(x: 159, y: 79), CGPoint(x: 80, y: 79)] {
            assertColor(actual.color(x: Int(point.x), y: Int(point.y)),
                        equals: expected.color(x: Int(point.x), y: Int(point.y)))
        }
    }

    func testOrientedPhoto_matchesUIKitPhotoOrientation() throws {
        let source = landscapePhoto()
        let pixels = try XCTUnwrap(source.cgImage)
        for orientation in [UIImage.Orientation.right, .left, .down, .upMirrored] {
            let oriented = UIImage(cgImage: pixels, scale: 1, orientation: orientation)
            let reference = makeImage(size: oriented.size) { rect in oriented.draw(in: rect) }
            let actual = try PixelBuffer(render(oriented, adjustment: .defaultValue, size: oriented.size))
            let expected = try PixelBuffer(reference)

            for y in stride(from: 5, to: actual.height, by: 10) {
                for x in stride(from: 5, to: actual.width, by: 10) {
                    assertColor(actual.color(x: x, y: y), equals: expected.color(x: x, y: y), tolerance: 0.015)
                }
            }
        }
    }

    func testEditorPhotoView_matchesExportCompositionAfterAdjustmentChanges() throws {
        let source = landscapePhoto()
        let (window, view) = makeHostedPhotoView(size: canvasSize)
        defer { removeHostedPhotoView(window) }
        view.update(image: source, adjustment: .defaultValue)
        var adjustment = fittedAdjustment(for: source)
        adjustment.offsetX = -0.1
        adjustment.offsetY = 0.04
        view.update(image: source, adjustment: adjustment)
        view.layoutIfNeeded()

        let scale = window.screen.scale
        let preview = try PixelBuffer(renderLayer(view.layer, size: canvasSize, scale: scale))
        let exported = try PixelBuffer(render(source, adjustment: adjustment, scale: scale))
        for y in stride(from: 2, to: preview.height, by: 11) {
            for x in stride(from: 2, to: preview.width, by: 11) {
                let actual = preview.color(x: x, y: y)
                let expected = exported.color(x: x, y: y)
                guard !colorsMatch(actual, expected, tolerance: 0.015) else { continue }
                XCTFail("Editor/export mismatch at (\(x), \(y)): \(actual), expected \(expected)")
                return
            }
        }
    }

    func testFractionalPhotoPlacement_atRetinaScalesLeavesNoDarkSeams() throws {
        let size = CGSize(width: 163, height: 327)
        for sourceSize in [CGSize(width: 173, height: 91), CGSize(width: 71, height: 193)] {
            let source = makeImage(size: sourceSize) { rect in
                UIColor.white.setFill()
                UIRectFill(rect)
            }
            let minimumScale = WallpaperCalendarBackgroundAdjustment.minimumScale(for: source.size, canvasSize: size)
            let background = WallpaperCalendarPhotoBackground(image: source)
            let (window, view) = makeHostedPhotoView(size: size)
            defer { removeHostedPhotoView(window) }
            let adjustments = [
                WallpaperCalendarBackgroundAdjustment(scale: minimumScale * 1.13, offsetX: 0.073, offsetY: 0.031),
                WallpaperCalendarBackgroundAdjustment(scale: minimumScale * 1.07, offsetX: -0.109, offsetY: -0.047),
                WallpaperCalendarBackgroundAdjustment(scale: minimumScale * 1.29, offsetX: 0.151, offsetY: -0.019)
            ]

            for scale in [CGFloat(2), CGFloat(3)] {
                for adjustment in adjustments {
                    background.update(size: size, adjustment: adjustment, contentsScale: scale)
                    view.update(image: source, adjustment: adjustment)
                    view.layoutIfNeeded()
                    for (name, layer) in [("export composition", background.layer), ("editor view", view.layer)] {
                        let pixels = try PixelBuffer(renderLayer(layer, size: size, scale: scale))
                        XCTAssertEqual(pixels.width, Int(size.width * scale))
                        XCTAssertEqual(pixels.height, Int(size.height * scale))
                        assertUniformWhite(pixels, description: "\(name), \(sourceSize), scale \(scale), \(adjustment)")
                    }
                }
            }
        }
    }

    func testExportedJPEG_outerEdgesMatchEditorWithoutDarkLines() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suite = "WallpaperCalendarPhotoBackgroundTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let fileManager = IsolatedFileManager(rootURL: directory)
        let store = WallpaperCalendarSettingsStore(defaults: defaults, fileManager: fileManager)
        let source = makeImage(size: CGSize(width: 173, height: 91)) { rect in
            UIColor.white.setFill()
            UIRectFill(rect)
        }
        _ = try store.saveBackgroundImageData(XCTUnwrap(source.pngData()))
        let size = CGSize(width: 163, height: 327)
        let adjustment = WallpaperCalendarBackgroundAdjustment(
            scale: WallpaperCalendarBackgroundAdjustment.minimumScale(for: source.size, canvasSize: size) * 1.13,
            offsetX: 0.073, offsetY: 0.031
        )
        _ = store.update { $0.backgroundAdjustment = adjustment }
        let renderer = WallpaperCalendarRenderer(settingsStore: store,
                                                  dataProvider: WallpaperCalendarDataProvider(),
                                                  fileManager: fileManager)
        let (window, view) = makeHostedPhotoView(size: size)
        defer { removeHostedPhotoView(window) }
        view.update(image: source, adjustment: adjustment)
        view.layoutIfNeeded()

        // Freeze both editor snapshots before exercising the independent export path.
        let scales = [CGFloat(2), CGFloat(3)]
        let editorImages = scales.map { renderLayer(view.layer, size: size, scale: $0) }
        for (scale, editorImage) in zip(scales, editorImages) {
            assertOpaque(try PixelBuffer(editorImage))
            let previewImage = makeImage(size: size, scale: scale) { rect in
                editorImage.draw(in: rect)
                UIColor.black.withAlphaComponent(0.18).setFill()
                UIBezierPath(rect: rect).fill()
            }
            let url = try renderer.render(force: true, now: Date(timeIntervalSince1970: 946_684_800),
                                          screenSize: size, scale: scale)
            let exported = try PixelBuffer(XCTUnwrap(UIImage(contentsOfFile: url.path)))
            let preview = try PixelBuffer(previewImage)
            XCTAssertEqual(exported.width, preview.width)
            XCTAssertEqual(exported.height, preview.height)
            // Calendar content starts at least 26pt from the sides. Check side and
            // top borders, including all corners, through the actual JPEG writer/decoder.
            let border = Int(8 * scale)
            for y in 0..<exported.height {
                for x in 0..<exported.width where x < border || x >= exported.width - border || y < border {
                    let actual = exported.color(x: x, y: y)
                    let expected = preview.color(x: x, y: y)
                    guard !colorsMatch(actual, expected, tolerance: 0.04) else { continue }
                    XCTFail("JPEG/editor mismatch at (\(x), \(y)), scale \(scale): \(actual), expected \(expected)")
                    return
                }
            }
        }
    }

    private func eventSnapshot(style: WallpaperCalendarGridStyle, category: Color,
                               continuesBeforeWeek: Bool = false) -> WallpaperCalendarSnapshot {
        let date = Date(timeIntervalSince1970: 946_684_800)
        let item = WallpaperCalendarItem(id: "single", sourceID: UUID(), title: "会議", categoryName: "Work",
                                         color: category, kind: .event, startDate: date, endDate: nil,
                                         isAllDay: false, priority: nil)

        let segment = CalendarWeekMultiDaySegment(id: "span", eventID: UUID(), title: "予定B8",
                                                   categoryName: "Work", color: category, lane: 0,
                                                   startColumn: 0, endColumn: 1, continuesBeforeWeek: continuesBeforeWeek,
                                                   continuesAfterWeek: false)
        let days = (0..<7).map { index in
            let row: WallpaperCalendarCellRowContent = index == 3 ? .item(item) : (index < 2 ? .multiDayPlaceholder : .empty)
            return WallpaperCalendarDay(date: date.addingTimeInterval(Double(index) * 86_400),
                                        previews: index == 3 ? [item] : [], rowContents: [row])
        }
        let week = WallpaperCalendarWeek(id: date, days: days,
                                         multiDayLayout: CalendarWeekMultiDayLayout(visibleLaneCount: 1, dayStates: [],
                                                                                  segments: [segment]))
        return WallpaperCalendarSnapshot(
            generatedAt: date, calendar: WallpaperCalendarDataProvider.calendar,
            rangeStart: date, rangeEndExclusive: date, weekdaySymbols: [],
            gridStyle: style, weeks: [week],
            fingerprintPayload: WallpaperCalendarFingerprintPayload(rangeStart: 0, rangeEndExclusive: 0,
                                                                     firstWeekday: 1, events: [], tasks: [])
        )
    }

    private func eventImages(snapshot: WallpaperCalendarSnapshot, photo: UIImage?, size: CGSize,
                             scale: CGFloat) throws -> (preview: UIImage, jpeg: UIImage) {
        let dark = WallpaperCalendarRenderer().resolveDarkAppearance(settings: .default, hasBackgroundImage: photo != nil)
        let image = WallpaperCalendarRenderer().renderImage(snapshot: snapshot, settings: .default, backgroundImage: photo,
                                                           isDarkAppearance: dark, size: size, scale: scale)
        let jpeg = try XCTUnwrap(UIImage(data: XCTUnwrap(image.jpegData(compressionQuality: 0.94)), scale: scale))
        let preview = WallpaperCalendarRenderView(snapshot: snapshot, settings: .default, backgroundImage: photo,
                                                  isDarkAppearance: dark).ignoresSafeArea()
        let controller = UIHostingController(rootView: preview)
        controller.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.isHidden = false
        defer { removeHostedPhotoView(window) }
        window.layoutIfNeeded()
        let previewImage = makeImage(size: size, scale: scale) { rect in
            controller.view.drawHierarchy(in: rect, afterScreenUpdates: true)
        }
        return (previewImage, jpeg)
    }

    private func landscapePhoto() -> UIImage {
        makeImage(size: CGSize(width: 160, height: 80)) { rect in
            UIColor.green.setFill()
            UIRectFill(rect)
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 160, height: 16))
            UIColor.blue.setFill()
            UIRectFill(CGRect(x: 0, y: 64, width: 160, height: 16))
            UIColor.magenta.setFill()
            UIRectFill(CGRect(x: 64, y: 30, width: 32, height: 20))
        }
    }

    private func fittedAdjustment(for image: UIImage) -> WallpaperCalendarBackgroundAdjustment {
        WallpaperCalendarBackgroundAdjustment(
            scale: WallpaperCalendarBackgroundAdjustment.minimumScale(for: image.size, canvasSize: canvasSize)
        )
    }

    private func makeHostedPhotoView(size: CGSize) -> (UIWindow, WallpaperCalendarPhotoBackgroundView.PhotoView) {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIViewController()
        controller.view = UIView(frame: window.bounds)
        window.rootViewController = controller
        let view = WallpaperCalendarPhotoBackgroundView.PhotoView(frame: CGRect(origin: .zero, size: size))
        controller.view.addSubview(view)
        // UIKit-backed layers need a visible hierarchy before an offscreen render.
        // This window never becomes key, and each test removes it on completion.
        window.isHidden = false
        window.layoutIfNeeded()
        view.layoutIfNeeded()
        return (window, view)
    }

    private func removeHostedPhotoView(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func render(_ image: UIImage,
                        adjustment: WallpaperCalendarBackgroundAdjustment,
                        size: CGSize? = nil,
                        scale: CGFloat = 1) -> UIImage {
        let size = size ?? canvasSize
        let background = WallpaperCalendarPhotoBackground(image: image)
        background.update(size: size, adjustment: adjustment, contentsScale: scale)
        return renderLayer(background.layer, size: size, scale: scale)
    }

    private func renderLayer(_ layer: CALayer, size: CGSize, scale: CGFloat = 1) -> UIImage {
        layer.layoutIfNeeded()
        layer.displayIfNeeded()
        return makeImage(size: size, scale: scale) { _ in
            if let context = UIGraphicsGetCurrentContext() { layer.render(in: context) }
        }
    }

    private func makeImage(size: CGSize, scale: CGFloat = 1, draw: (CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(CGRect(origin: .zero, size: size))
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertOpaque(_ pixels: PixelBuffer, file: StaticString = #filePath, line: UInt = #line) {
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                guard pixels.color(x: x, y: y).alpha < 0.99 else { continue }
                XCTFail("Transparent background pixel at (\(x), \(y))", file: file, line: line)
                return
            }
        }
    }

    private func assertUniformWhite(_ pixels: PixelBuffer,
                                    description: String,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        // White over the composition's black base exposes both transparent holes
        // and black antialiasing seams, including the outermost canvas pixels.
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let color = pixels.color(x: x, y: y)
                guard color.red < 0.99 || color.green < 0.99 || color.blue < 0.99 || color.alpha < 0.99 else { continue }
                XCTFail("Dark or transparent seam at (\(x), \(y)): \(color), \(description)", file: file, line: line)
                return
            }
        }
    }

    private enum EdgeColor {
        case red
        case blue
    }

    private func assertDominantEdgeColor(_ color: PixelColor,
                                         channel: EdgeColor,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) {
        let dominant = channel == .red ? color.red : color.blue
        let other = max(color.green, channel == .red ? color.blue : color.red)
        XCTAssertGreaterThan(dominant, 0.7, "Edge color was lost", file: file, line: line)
        XCTAssertGreaterThan(dominant - other, 0.3, "Wrong edge color or repeated subject", file: file, line: line)
        XCTAssertGreaterThanOrEqual(color.alpha, 0.99, file: file, line: line)
    }

    private func assertColor(_ actual: PixelColor,
                             equals expected: UIColor,
                             tolerance: Double = 0.025,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        expected.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        assertColor(actual, equals: PixelColor(red: red, green: green, blue: blue, alpha: alpha),
                    tolerance: tolerance, file: file, line: line)
    }

    private func assertColor(_ actual: PixelColor,
                             equals expected: PixelColor,
                             tolerance: Double = 0.025,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        XCTAssertEqual(actual.red, expected.red, accuracy: tolerance, "Red", file: file, line: line)
        XCTAssertEqual(actual.green, expected.green, accuracy: tolerance, "Green", file: file, line: line)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: tolerance, "Blue", file: file, line: line)
        XCTAssertEqual(actual.alpha, expected.alpha, accuracy: tolerance, "Alpha", file: file, line: line)
    }

    private func colorsMatch(_ actual: PixelColor, _ expected: PixelColor, tolerance: Double) -> Bool {
        abs(actual.red - expected.red) <= tolerance &&
            abs(actual.green - expected.green) <= tolerance &&
            abs(actual.blue - expected.blue) <= tolerance &&
            abs(actual.alpha - expected.alpha) <= tolerance
    }

    private struct PixelColor {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
            self.red = Double(red)
            self.green = Double(green)
            self.blue = Double(blue)
            self.alpha = Double(alpha)
        }
    }

    private struct PixelBuffer {
        let width: Int
        let height: Int
        private let data: [UInt8]

        init(_ image: UIImage) throws {
            let cgImage = try XCTUnwrap(image.cgImage)
            let width = cgImage.width
            let height = cgImage.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            self.width = width
            self.height = height
            data = pixels
        }

        func color(x: Int, y: Int) -> PixelColor {
            let offset = (y * width + x) * 4
            return PixelColor(red: CGFloat(data[offset]) / 255,
                              green: CGFloat(data[offset + 1]) / 255,
                              blue: CGFloat(data[offset + 2]) / 255,
                              alpha: CGFloat(data[offset + 3]) / 255)
        }
    }

    final class IsolatedFileManager: FileManager, @unchecked Sendable {
        private let rootURL: URL

        init(rootURL: URL) {
            self.rootURL = rootURL
            super.init()
        }

        override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
            rootURL
        }
    }
}
