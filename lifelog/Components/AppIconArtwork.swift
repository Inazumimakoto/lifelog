import CoreGraphics

/// Coordinates are measured on the shipped 1024-point icon, with the origin at the top left.
/// Shared by the Settings preview, launch animation, and icon asset generator.
enum AppIconArtwork {
    static let dimension: CGFloat = 1024
    static let dotBounds = CGRect(x: 572, y: 559, width: 203, height: 203)
    static let stem: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 253, y: 253))
        path.addLine(to: CGPoint(x: 403, y: 253))
        path.addLine(to: CGPoint(x: 561, y: 783))
        path.addLine(to: CGPoint(x: 407, y: 783))
        path.closeSubpath()
        return path
    }()

    static func draw(_ palette: AppIconPalette, in context: CGContext, size: CGSize) {
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: size.width / dimension, y: size.height / dimension)
        context.setFillColor(color(palette.backgroundHex))
        context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))

        context.setFillColor(color(palette.stemHex))
        context.addPath(stem)
        context.fillPath()

        context.setFillColor(color(palette.accentHex))
        context.fillEllipse(in: dotBounds)
    }

    private static func color(_ hex: String) -> CGColor {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else {
            preconditionFailure("Invalid bundled icon color: \(hex)")
        }
        return CGColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255,
                       alpha: 1)
    }
}
