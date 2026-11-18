import SwiftUI

struct AppThemeSettingsView: View {
    @AppStorage(AppTheme.selectionKey) private var storedSelection: String?
    @AppStorage(AppTheme.legacyBackgroundKey) private var legacyBackground = ""
    @AppStorage(AppIconPalette.followsThemeKey) private var iconFollowsTheme = true
    @Environment(\.deviceColorScheme) private var deviceColorScheme
    @EnvironmentObject private var appIconCoordinator: AppIconCoordinator

    private var selection: AppTheme.Selection {
        AppTheme.Selection(storedValue: storedSelection, legacyBackground: legacyBackground)
    }

    var body: some View {
        Form {
            iconSection
            Section {
                themeButton("appTheme.system", choice: .system) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.title2)
                }
                ForEach(AppTheme.Preset.allCases) { preset in
                    themeButton(preset.localizedName, choice: preset.selection) {
                        Circle()
                            .fill(AppTheme.color(hex: preset.selection.backgroundHex))
                            .overlay(Circle().strokeBorder(.primary.opacity(0.25)))
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(AppTheme.color(hex: preset.selection.accentHex))
                                    .frame(width: 14, height: 14)
                            }
                    }
                }
            }
            Section {
                ColorPicker("背景色", selection: backgroundColor, supportsOpacity: false)
                ColorPicker("appTheme.accentColor", selection: accentColor, supportsOpacity: false)
            } header: {
                Text("appTheme.custom")
            } footer: {
                Text("appTheme.colorDescription")
            }
        }
        .appThemeBackground()
        .navigationTitle("appTheme.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { appIconCoordinator.beginEditing() }
        .onDisappear { appIconCoordinator.endEditing() }
    }

    private var iconSection: some View {
        let palette = AppIconPalette.resolve(
            selection: selection,
            followsTheme: iconFollowsTheme,
            systemColorScheme: deviceColorScheme
        )
        return Section {
            Toggle(isOn: $iconFollowsTheme) {
                HStack(spacing: 12) {
                    AppIconPreview(palette: palette)
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                    Text("appTheme.iconFollowsTheme")
                }
            }
            if let failure = appIconCoordinator.failure {
                switch failure {
                case .unsupported:
                    Text("appTheme.iconUnavailable")
                        .font(.footnote)
                case .changeFailed:
                    Text("appTheme.iconError")
                        .font(.footnote)
                    Button("appTheme.retryIcon") { appIconCoordinator.retry() }
                }
            }
        } header: {
            Text("appTheme.homeScreenIcon")
        } footer: {
            Text("appTheme.iconDescription")
        }
    }

    private var backgroundColor: Binding<Color> {
        Binding {
            AppTheme.color(hex: selection.backgroundHex)
        } set: { color in
            if let hex = AppTheme.hex(from: color) {
                storedSelection = AppTheme.Selection(backgroundHex: hex, accentHex: selection.accentHex).storedValue
            }
        }
    }

    private var accentColor: Binding<Color> {
        Binding {
            Color(hex: selection.accentHex) ?? .accentColor
        } set: { color in
            if let hex = AppTheme.hex(from: color) {
                storedSelection = AppTheme.Selection(backgroundHex: selection.backgroundHex, accentHex: hex).storedValue
            }
        }
    }

    private func themeButton(
        _ title: LocalizedStringKey,
        choice: AppTheme.Selection,
        @ViewBuilder swatch: () -> some View
    ) -> some View {
        let selected = selection == choice
        return Button {
            storedSelection = choice.storedValue
        } label: {
            HStack(spacing: 12) {
                swatch()
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                Text(title)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension AppTheme.Preset {
    var localizedName: LocalizedStringKey {
        switch self {
        case .whiteBlue: "appTheme.whiteBlue"
        case .blackBlue: "appTheme.blackBlue"
        case .mint: "appTheme.mint"
        case .sky: "appTheme.sky"
        case .lavender: "appTheme.lavender"
        case .rose: "appTheme.rose"
        case .forest: "appTheme.forest"
        case .midnight: "appTheme.midnight"
        }
    }
}
