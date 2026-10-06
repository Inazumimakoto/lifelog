import Foundation
import CoreGraphics

nonisolated struct ReviewMapLabelCandidate {
    let id: String
    let frame: CGRect
    let latestDate: Date
    let isSelected: Bool
}

/// Date labels may be omitted for space; place markers are always retained.
nonisolated enum ReviewMapLabelLayout {
    static func visibleIDs(for candidates: [ReviewMapLabelCandidate],
                           in bounds: CGRect,
                           avoiding reservedFrames: [CGRect] = []) -> Set<String> {
        let ordered = candidates.sorted {
            if $0.isSelected != $1.isSelected { return $0.isSelected }
            if $0.latestDate != $1.latestDate { return $0.latestDate > $1.latestDate }
            return $0.id < $1.id
        }
        var occupied = OccupiedFrames(reservedFrames)
        var visible: Set<String> = []
        for candidate in ordered {
            let frame = candidate.frame.insetBy(dx: -3, dy: -3)
            guard bounds.contains(frame),
                  !occupied.intersects(frame) else { continue }
            visible.insert(candidate.id)
            occupied.insert(frame)
        }
        return visible
    }

    /// A grid limits rectangle checks to nearby labels/markers while retaining CGRect's
    /// exact intersection behavior, including reserved frames spanning multiple cells.
    private nonisolated struct OccupiedFrames {
        private nonisolated struct Cell: Hashable {
            let x: Int
            let y: Int
        }

        private static let cellSize: CGFloat = 64
        private static let maximumCells = 4_096
        private var frames: [CGRect] = []
        private var cells: [Cell: [Int]] = [:]
        private var oversizedFrameIDs: [Int] = []

        init(_ initialFrames: [CGRect]) {
            for frame in initialFrames { insert(frame) }
        }

        mutating func insert(_ frame: CGRect) {
            let index = frames.count
            frames.append(frame)
            guard let coveredCells = coveredCells(for: frame) else {
                oversizedFrameIDs.append(index)
                return
            }
            for cell in coveredCells {
                cells[cell, default: []].append(index)
            }
        }

        func intersects(_ frame: CGRect) -> Bool {
            guard let coveredCells = coveredCells(for: frame) else {
                return frames.contains { $0.intersects(frame) }
            }
            if oversizedFrameIDs.contains(where: { frames[$0].intersects(frame) }) { return true }
            var checked: Set<Int> = []
            for cell in coveredCells {
                for index in cells[cell, default: []] where checked.insert(index).inserted {
                    if frames[index].intersects(frame) { return true }
                }
            }
            return false
        }

        private func coveredCells(for frame: CGRect) -> [Cell]? {
            let minX = floor(frame.minX / Self.cellSize)
            let maxX = floor(frame.maxX / Self.cellSize)
            let minY = floor(frame.minY / Self.cellSize)
            let maxY = floor(frame.maxY / Self.cellSize)
            guard minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite,
                  minX > CGFloat(Int.min), maxX < CGFloat(Int.max),
                  minY > CGFloat(Int.min), maxY < CGFloat(Int.max) else { return nil }
            let columns = maxX - minX + 1
            let rows = maxY - minY + 1
            guard columns > 0, rows > 0,
                  columns * rows <= CGFloat(Self.maximumCells) else { return nil }
            var result: [Cell] = []
            result.reserveCapacity(Int(columns * rows))
            for x in Int(minX)...Int(maxX) {
                for y in Int(minY)...Int(maxY) {
                    result.append(Cell(x: x, y: y))
                }
            }
            return result
        }
    }
}
