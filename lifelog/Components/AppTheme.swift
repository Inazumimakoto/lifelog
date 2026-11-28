import SwiftUI

/// The app's screens share a background and an accent. Wallpaper and calendar category colors
/// have their own settings (see docs/ui-guidelines.md).
struct AppTheme: Equatable {
    static let legacyBackgroundKey = "appThemeBackgroundHex"
    static let selectionKey = "appThemeColorPair"

    struct Selection: Equatable {
        let backgroundHex: String
        let accentHex: String
        static let system = Selection(backgroundHex: "", accentHex: "")

        init(backgroundHex: String, accentHex: String) {
            self.backgroundHex = normalizedRGBHex(backgroundHex) ?? ""
            self.accentHex = normalizedRGBHex(accentHex) ?? ""
        }

        // Store both values in one defaults entry. An empty component inherits
        // its system color; an explicitly saved system pair overrides legacy data.
        var storedValue: String { backgroundHex + "|" + accentHex }

        init(storedValue: String?, legacyBackground: String) {
            if let storedValue {
                let parts = storedValue.components(separatedBy: "|")
                guard parts.count == 2 else { self = .system; return }
                self.init(backgroundHex: parts[0], accentHex: parts[1])
            } else if let previous = normalizedRGBHex(legacyBackground) {
                self = Preset.legacyPresets.lazy.map(\.selection).first { $0.backgroundHex == previous }
                    ?? Selection(backgroundHex: previous, accentHex: "")
            } else {
                self = .system
            }
        }
    }

    enum Preset: CaseIterable, Identifiable {
        case whiteBlue, blackBlue, mint, sky, lavender, rose, forest, midnight
        var id: Self { self }

        // Only these six pairs existed when a theme was stored as a background alone.
        static let legacyPresets: [Self] = [.mint, .sky, .lavender, .rose, .forest, .midnight]

        var selection: Selection {
            let palette: AppIconPalette = switch self {
            case .whiteBlue: .whiteBlue
            case .blackBlue: .blackBlue
            case .mint: .mint
            case .sky: .sky
            case .lavender: .lavender
            case .rose: .rose
            case .forest: .forest
            case .midnight: .midnight
            }
            return Selection(backgroundHex: palette.backgroundHex, accentHex: palette.accentHex)
        }
    }

    let background: Color
    let colorScheme: ColorScheme?
    let accent: Color?
    let onAccent: Color
    let selectionIndicator: Color

    init?(selection: Selection, systemColorScheme: ColorScheme = .light) {
        guard selection != .system else { return nil }
        let customBackground = Color(hex: selection.backgroundHex)
        background = customBackground ?? Color(uiColor: .systemBackground)
        accent = Color(hex: selection.accentHex)

        var environment = EnvironmentValues()
        environment.colorScheme = systemColorScheme
        let canvasLuminance = Self.luminance(background, in: environment)
        colorScheme = customBackground.map { _ in Self.prefersBlack(on: canvasLuminance) ? .light : .dark }
        environment.colorScheme = colorScheme ?? systemColorScheme
        let controlColor = accent ?? Color(uiColor: .systemBlue)
        let accentLuminance = Self.luminance(controlColor, in: environment)
        onAccent = Self.prefersBlack(on: accentLuminance) ? .black : .white
        let contrast = (max(canvasLuminance, accentLuminance) + 0.05) / (min(canvasLuminance, accentLuminance) + 0.05)
        selectionIndicator = contrast >= 3 ? controlColor : .primary
    }

    static func luminance(_ color: Color, in environment: EnvironmentValues) -> Float {
        let rgb = color.resolve(in: environment)
        return 0.2126 * rgb.linearRed + 0.7152 * rgb.linearGreen + 0.0722 * rgb.linearBlue
    }

    static func prefersBlack(on luminance: Float) -> Bool {
        (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }

    static func color(hex: String) -> Color {
        Color(hex: hex) ?? Color(uiColor: .systemBackground)
    }

    static func hex(from color: Color) -> String? {
        // The system picker can supply Display P3, grayscale, or extended sRGB.
        // Persist the same sRGB space that Color(hex:) reads.
        let rgb = color.resolve(in: EnvironmentValues())
        let channels = [rgb.red, rgb.green, rgb.blue]
        guard channels.allSatisfy(\.isFinite) else { return nil }
        let bytes = channels.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}

extension AppIconPalette {
    static func resolve(selection: AppTheme.Selection, followsTheme: Bool, systemColorScheme: ColorScheme) -> Self {
        guard followsTheme, selection != .system else {
            return systemColorScheme == .dark ? .primaryDark : .primaryLight
        }
        let background = selection.backgroundHex.isEmpty
            ? (systemColorScheme == .dark ? "#000000" : "#FFFFFF")
            : selection.backgroundHex
        if !selection.accentHex.isEmpty {
            return closest(backgroundHex: background, accentHex: selection.accentHex)
        }
        let scheme = AppTheme(selection: selection, systemColorScheme: systemColorScheme)?.colorScheme ?? systemColorScheme
        let traits = UITraitCollection(userInterfaceStyle: UIUserInterfaceStyle(scheme))
        let systemBlue = UIColor.systemBlue.resolvedColor(with: traits)
        let accent = AppTheme.hex(from: Color(uiColor: systemBlue)) ?? (scheme == .dark ? "#0A84FF" : "#007AFF")
        return closest(backgroundHex: background, accentHex: accent)
    }
}

private struct DeviceColorSchemeKey: EnvironmentKey {
    static let defaultValue = ColorScheme.light
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme? = nil
}

extension EnvironmentValues {
    var deviceColorScheme: ColorScheme {
        get { self[DeviceColorSchemeKey.self] }
        set { self[DeviceColorSchemeKey.self] = newValue }
    }

    var appTheme: AppTheme? {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

private struct AppThemeBackground: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        let hasBackground = theme?.colorScheme != nil
        content
            .scrollContentBackground(hasBackground ? .hidden : .automatic)
            .frame(maxWidth: hasBackground ? .infinity : nil, maxHeight: hasBackground ? .infinity : nil)
            .background {
                if hasBackground, let theme {
                    theme.background.ignoresSafeArea()
                }
            }
    }
}

struct AppThemeAppearance: ViewModifier {
    let canChangeIcon: Bool
    @AppStorage(AppTheme.selectionKey) private var storedSelection: String?
    @AppStorage(AppTheme.legacyBackgroundKey) private var legacyBackground = ""
    @AppStorage(AppIconPalette.followsThemeKey) private var iconFollowsTheme = true
    @Environment(\.colorScheme) private var inheritedScheme
    @EnvironmentObject private var appIconCoordinator: AppIconCoordinator
    @State private var sceneScheme: ColorScheme?
    @State private var observedSceneCache = ObservedSceneCache()

    private final class ObservedSceneCache {
        var scheme: ColorScheme?
    }

    private struct IconUpdate: Equatable {
        let name: String?
        let isActive: Bool
    }

    func body(content: Content) -> some View {
        let selection = AppTheme.Selection(storedValue: storedSelection, legacyBackground: legacyBackground)
        let resolvedObserved = sceneScheme ?? observedSceneCache.scheme
        let systemScheme = resolvedObserved ?? inheritedScheme
        let theme = AppTheme(selection: selection, systemColorScheme: systemScheme)
        let palette = AppIconPalette.resolve(selection: selection, followsTheme: iconFollowsTheme, systemColorScheme: systemScheme)
        let update = IconUpdate(name: palette.alternateName, isActive: canChangeIcon && resolvedObserved != nil)
        content
            .environment(\.appTheme, theme)
            .environment(\.deviceColorScheme, systemScheme)
            .accentColor(theme?.accent)
            .tint(theme?.accent)
            .background {
                AppThemeWindowAppearance(colorScheme: theme?.colorScheme) { reported in
                    observedSceneCache.scheme = reported
                    // Avoid triggering a redundant full-root SwiftUI re-render on Frame 1
                    // when the observed scene already matches the inherited scheme.
                    if reported != systemScheme || (canChangeIcon && sceneScheme == nil) {
                        sceneScheme = reported
                    }
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            .onChange(of: update, initial: true) { _, newValue in
                appIconCoordinator.update(targetName: newValue.name, isActive: newValue.isActive)
            }
    }
}

/// Apply appearance once per window so already-presented sheets inherit changes.
/// Read the device appearance from the scene above the window's override.
private struct AppThemeWindowAppearance: UIViewRepresentable {
    let colorScheme: ColorScheme?
    let onSystemSchemeChange: (ColorScheme) -> Void

    final class WindowObserver: UIView {
        var style = UIUserInterfaceStyle.unspecified {
            didSet { applyStyle() }
        }
        var onSystemSchemeChange: ((ColorScheme) -> Void)?
        private weak var observedScene: UIWindowScene?
        private var registration: (any UITraitChangeRegistration)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyStyle()
            let scene = window?.windowScene
            guard observedScene !== scene else { return }
            if let registration { observedScene?.unregisterForTraitChanges(registration) }
            observedScene = scene
            registration = scene?.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: UIWindowScene, _: UITraitCollection) in
                self?.reportSystemScheme()
            }
            reportSystemScheme()
        }

        private func reportSystemScheme() {
            // didMoveToWindow can run during a SwiftUI view update.
            DispatchQueue.main.async { [weak self] in
                guard let self, let style = observedScene?.traitCollection.userInterfaceStyle, style != .unspecified else { return }
                onSystemSchemeChange?(style == .dark ? .dark : .light)
            }
        }

        private func applyStyle() {
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
        }
    }

    func makeUIView(context: Context) -> WindowObserver { WindowObserver() }

    func updateUIView(_ view: WindowObserver, context: Context) {
        view.onSystemSchemeChange = onSystemSchemeChange
        view.style = UIUserInterfaceStyle(colorScheme)
    }
}

extension View {
    func appThemeBackground() -> some View {
        modifier(AppThemeBackground())
    }
}
