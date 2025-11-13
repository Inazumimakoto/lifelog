//
//  PhotoStorage.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import SwiftUI
import UIKit

enum PhotoStorage {
    static func save(data: Data, fileName: String = UUID().uuidString) throws -> String {
        let url = try directoryURL().appendingPathComponent("\(fileName).jpg")
        try data.write(to: url, options: .atomic)
        return url.path
    }

    static func loadImage(at path: String) -> Image? {
        guard let data = FileManager.default.contents(atPath: path),
              let uiImage = UIImage(data: data) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }

    static func delete(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private static func directoryURL() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "PhotoStorage", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to locate documents directory"])
        }
        let folder = url.appendingPathComponent("DiaryPhotos", isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) == false {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }
}
