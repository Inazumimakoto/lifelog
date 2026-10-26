import Foundation
import UIKit

/// Decode before handing pixels to SwiftUI/UIKit. Serial decoding avoids many
/// competing image workers; overlapping requests share one local file read.
nonisolated final class PhotoImageLoader: @unchecked Sendable {
    static let shared = PhotoImageLoader()

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: [String: [CheckedContinuation<UIImage?, Never>]] = [:]

    init(queue: DispatchQueue = DispatchQueue(label: "PhotoStorage.Decode", qos: .userInitiated)) {
        self.queue = queue
    }

    func load(key: String, operation: @escaping @Sendable () -> UIImage?) async -> UIImage? {
        guard !_Concurrency.Task.isCancelled else { return nil }
        return await withCheckedContinuation { continuation in
            lock.lock()
            if pending[key] != nil {
                pending[key]?.append(continuation)
                lock.unlock()
                return
            }
            pending[key] = [continuation]
            lock.unlock()

            queue.async { [self] in
                let image = autoreleasepool(invoking: operation)
                lock.lock()
                let waiters = pending.removeValue(forKey: key) ?? []
                lock.unlock()
                for waiter in waiters { waiter.resume(returning: image) }
            }
        }
    }

    /// Prefetch operations also use the same serial decoder. At most one
    /// operation from each prefetch queue is waiting, leaving visible loads free
    /// to enter the queue between prefetched photos.
    func perform(_ operation: () -> UIImage?) -> UIImage? {
        queue.sync { autoreleasepool(invoking: operation) }
    }

    static func preparedImage(at url: URL) -> UIImage? {
        UIImage(contentsOfFile: url.path)?.preparingForDisplay()
    }

    static func preparedImage(from data: Data) -> UIImage? {
        UIImage(data: data)?.preparingForDisplay()
    }
}
