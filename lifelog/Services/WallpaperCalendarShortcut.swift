import Foundation

/// Distribution setup: docs/wallpaper-shortcut-distribution.md.
enum WallpaperCalendarShortcut {
    static var installationURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "WallpaperCalendarShortcutURL") as? String,
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https",
              url.host == "www.icloud.com",
              url.user == nil,
              url.password == nil,
              url.port == nil else {
            return nil
        }

        let components = url.pathComponents
        guard components.count == 3,
              components[1] == "shortcuts",
              components[2].count == 32,
              components[2].allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            return nil
        }
        return url
    }
}
