import Foundation

enum LetterPhotoFiles {
    /// Old letters may contain absolute paths; newer letters store Documents-relative paths.
    static func resolvePath(_ path: String) -> String {
        resolvePath(path, documentsDirectory: FileManager.default.urls(for: .documentDirectory,
                                                                      in: .userDomainMask).first)
    }

    static func resolvePath(_ path: String, documentsDirectory: URL?) -> String {
        guard path.hasPrefix("/") == false, let documentsDirectory else { return path }
        return documentsDirectory.appendingPathComponent(path).path
    }
}
