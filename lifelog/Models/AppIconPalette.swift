import Foundation

/// iOS installs alternate icons from the app bundle. The generator and the app share this table.
struct AppIconPalette: Equatable {
    static let followsThemeKey = "appIconFollowsTheme"

    let alternateName: String?
    let backgroundHex: String
    let accentHex: String
    let stemHex: String

    static let primaryLight = Self(alternateName: nil, backgroundHex: "#FFFFFF", accentHex: "#0080FE", stemHex: "#202020")
    static let primaryDark = Self(alternateName: nil, backgroundHex: "#090909", accentHex: "#007EFE", stemHex: "#F4F4F4")

    static let whiteBlue = named("WhiteBlue", "#FFFFFF", "#006BD6")
    static let blackBlue = named("BlackBlue", "#000000", "#0A84FF")
    static let mint = named("Mint", "#CFE9D8", "#176344")
    static let sky = named("Sky", "#CDE4F5", "#175D87")
    static let lavender = named("Lavender", "#E2DCF4", "#694399")
    static let rose = named("Rose", "#F4D9DE", "#9B3D5C")
    static let forest = named("Forest", "#174B39", "#9DE6B5")
    static let midnight = named("Midnight", "#19263B", "#ADC9FF")

    static let alternates: [Self] = {
        let presets = [whiteBlue, blackBlue, mint, sky, lavender, rose, forest, midnight]
        let backgrounds = [
            "#FFFFFF", "#000000", "#82858A", "#CFE9D8", "#CDE4F5", "#E2DCF4", "#F4D9DE", "#FFE7AD",
            "#174B39", "#19263B", "#50304B", "#613D24", "#318970", "#367CD2", "#A568C0", "#D95169", "#EBA834"
        ]
        let accents = [
            "#16181C", "#F7F9FF", "#1479F5", "#E63C66", "#ED8829", "#F5D440",
            "#25A65E", "#29C7CD", "#8D53CD", "#F4AFD5"
        ]
        return presets + backgrounds.flatMap { background in
            accents.map { accent in
                named("RGB" + background.dropFirst() + accent.dropFirst(), background, accent)
            }
        }
    }()

    private static func named(_ name: String, _ background: String, _ accent: String) -> Self {
        let color = IconColor(background)
        let useBlack = (color.luminance + 0.05) / 0.05 >= 1.05 / (color.luminance + 0.05)
        return Self(alternateName: "AppIcon" + name, backgroundHex: background,
                    accentHex: accent, stemHex: useBlack ? "#000000" : "#FFFFFF")
    }

    private static let samples = alternates.map {
        (palette: $0, background: IconColor($0.backgroundHex), accent: IconColor($0.accentHex))
    }

    static func closest(backgroundHex: String, accentHex: String) -> Self {
        let background = IconColor(backgroundHex)
        let accent = IconColor(accentHex)
        var best = whiteBlue
        var lowestDistance = Double.infinity
        for sample in samples {
            let distance = 1.25 * background.distance(to: sample.background) + accent.distance(to: sample.accent)
            if distance < lowestDistance {
                lowestDistance = distance
                best = sample.palette
                if distance == 0 { break }
            }
        }
        return best
    }
}

/// Squared distance in OKLab compares both lightness and hue on a perceptually uniform scale.
private struct IconColor {
    let luminance: Double
    let lab: SIMD3<Double>

    init(_ hex: String) {
        guard hex.count == 7, hex.first == "#", let rgb = UInt32(hex.dropFirst(), radix: 16) else {
            preconditionFailure("Expected a normalized sRGB icon color")
        }
        func linear(_ shift: Int) -> Double {
            let value = Double((rgb >> shift) & 255) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r = linear(16), g = linear(8), b = linear(0)
        luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        lab = SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    func distance(to other: Self) -> Double {
        let delta = lab - other.lab
        return (delta * delta).sum()
    }
}
