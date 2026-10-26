import UIKit

/// Use the same portrait canvas when adjusting, previewing and exporting a wallpaper.
/// See docs/requirements.md §4.11.
@MainActor
enum WallpaperCalendarCanvas {
    static var size: CGSize {
        let size = UIScreen.main.fixedCoordinateSpace.bounds.size
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else {
            return CGSize(width: 393, height: 852)
        }
        return CGSize(width: min(size.width, size.height), height: max(size.width, size.height))
    }

    static var scale: CGFloat {
        let scale = UIScreen.main.scale
        return scale.isFinite && scale > 0 ? scale : 1
    }
}
