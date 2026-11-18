// From the repository root:
// swiftc lifelog/Models/AppIconPalette.swift lifelog/Components/AppIconArtwork.swift tools/GenerateAppIcons.swift -o /tmp/lifelify-generate-icons
// /tmp/lifelify-generate-icons
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct GenerateAppIcons {
    private static let catalog = URL(fileURLWithPath: "lifelog/Assets.xcassets", isDirectory: true)
    private static let primary = catalog.appendingPathComponent("AppIcon.appiconset")
    private static let info: [String: Any] = ["author": "xcode", "version": 1]

    static func main() throws {
        let alternates = catalog.appendingPathComponent("AlternateAppIcons")
        try FileManager.default.createDirectory(at: alternates, withIntermediateDirectories: true)
        try writeContents(["info": info], to: alternates)

        for palette in AppIconPalette.alternates {
            guard let name = palette.alternateName else { throw GenerationError.missingAlternateName }
            let set = alternates.appendingPathComponent("\(name).appiconset")
            try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
            let dimension = Int(AppIconArtwork.dimension)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: dimension, height: dimension,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw GenerationError.couldNotRender(name)
            }
            context.translateBy(x: 0, y: CGFloat(dimension))
            context.scaleBy(x: 1, y: -1)
            AppIconArtwork.draw(palette, in: context, size: CGSize(width: dimension, height: dimension))
            guard let image = context.makeImage() else { throw GenerationError.couldNotRender(name) }
            try writePNG(image, to: set.appendingPathComponent("icon.png"))

            // A dark Home Screen uses the same chosen palette. Both entries
            // reference one opaque PNG; the system handles its tinted appearance.
            let universal = ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon.png"]
            var dark: [String: Any] = universal
            dark["appearances"] = [["appearance": "luminosity", "value": "dark"]]
            try writeContents(["images": [universal, dark], "info": info], to: set)
        }
        try makePrimaryPreview()
    }

    private static func makePrimaryPreview() throws {
        let set = catalog.appendingPathComponent("AppIconPrimaryPreview.imageset")
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        let sourceFiles = ["lifelify_final_icon.png", "lifelify_dark_icon.png"]
        var images: [[String: Any]] = []
        for (index, sourceName) in sourceFiles.enumerated() {
            let source = primary.appendingPathComponent(sourceName)
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 192
            ]
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let preview = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                throw GenerationError.couldNotRender(sourceName)
            }
            let file = index == 0 ? "primary.png" : "primary-dark.png"
            try writePNG(preview, to: set.appendingPathComponent(file))
            var entry: [String: Any] = ["idiom": "universal", "filename": file]
            if index == 1 { entry["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
            images.append(entry)
        }
        try writeContents(["images": images, "info": info], to: set)
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw GenerationError.couldNotRender(url.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GenerationError.couldNotRender(url.path) }
    }

    private static func writeContents(_ value: [String: Any], to directory: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        try data.write(to: directory.appendingPathComponent("Contents.json"))
    }

    private enum GenerationError: Error {
        case missingAlternateName
        case couldNotRender(String)
    }
}
