import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// PhotosPicker lends its file only for the transfer callback. Keep an owned
/// copy until the importer has stored it, without materializing a movie as Data.
nonisolated struct ImportedDiaryVideo: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("DiaryVideoImports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = directory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            do {
                try FileManager.default.copyItem(at: received.file, to: destination)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
                return Self(url: destination)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
    }

    func removeTemporaryFile() {
        try? FileManager.default.removeItem(at: url)
    }
}
