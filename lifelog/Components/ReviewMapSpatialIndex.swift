import MapKit

/// docs/requirements.md §4.4.2: viewport and tap queries retain each place's identity
/// while avoiding coordinate projection and a scan of every saved place on camera changes.
/// Coordinates outside the finite Web Mercator world are omitted. Longitude wraps at
/// the date line; the two coordinate representations of that line share x = 0.
nonisolated struct ReviewMapSpatialIndex: Sendable {
    nonisolated struct QueryResult: Sendable {
        let indices: [Int]
        let visitedNodeCount: Int
        let examinedPointCount: Int
    }

    private let points: [Point]
    private let nodes: [Node]
    private let originalIndices: [Int]

    /// A cancelled refresh abandons construction and produces an empty index.
    init(coordinates: [CLLocationCoordinate2D]) {
        let world = MKMapRect.world
        var projected: [Point] = []
        projected.reserveCapacity(coordinates.count)
        for (index, coordinate) in coordinates.enumerated() {
            if index.isMultiple(of: 128), _Concurrency.Task.isCancelled {
                points = []
                nodes = []
                originalIndices = []
                return
            }
            guard CLLocationCoordinate2DIsValid(coordinate) else { continue }
            let point = MKMapPoint(coordinate)
            guard point.x.isFinite, point.y.isFinite,
                  point.y >= 0, point.y <= world.size.height else { continue }
            var x = point.x.truncatingRemainder(dividingBy: world.size.width)
            if x < 0 { x += world.size.width }
            projected.append(Point(x: x, y: point.y, originalIndex: index))
        }
        var builder = Builder()
        if !projected.isEmpty { builder.append(projected, depth: 0) }
        if _Concurrency.Task.isCancelled {
            points = []
            nodes = []
            originalIndices = []
            return
        }
        originalIndices = projected.map(\.originalIndex)
        points = builder.points
        nodes = builder.nodes
    }

    /// Returns exact projected candidates in original array order, including separate
    /// places at the same coordinate. Rectangles may cross the date line or sit in a
    /// repeated horizontal map world; rectangle edges are inclusive.
    func indices(in mapRect: MKMapRect) -> [Int] {
        query(in: mapRect).indices
    }

    /// Counts allow deterministic verification that small viewports prune distant
    /// places without timing assertions. Only leaf point containment checks are counted.
    func query(in mapRect: MKMapRect) -> QueryResult {
        let bounds = Self.searchBounds(for: mapRect)
        guard let root = nodes.first, !bounds.isEmpty else {
            return QueryResult(indices: [], visitedNodeCount: 0, examinedPointCount: 0)
        }
        if bounds.contains(where: { $0.contains(root.bounds) }) {
            return QueryResult(indices: originalIndices, visitedNodeCount: 1, examinedPointCount: 0)
        }
        var indices: [Int] = []
        var visitedNodeCount = 0
        var examinedPointCount = 0
        for searchBounds in bounds {
            var pending = [0]
            while let nodeIndex = pending.popLast() {
                visitedNodeCount += 1
                let node = nodes[nodeIndex]
                guard searchBounds.intersects(node.bounds) else { continue }
                if searchBounds.contains(node.bounds) {
                    indices.append(contentsOf: points[node.pointRange].map(\.originalIndex))
                } else if node.children.isEmpty {
                    examinedPointCount += node.pointRange.count
                    for point in points[node.pointRange] where searchBounds.contains(point) {
                        indices.append(point.originalIndex)
                    }
                } else {
                    pending.append(contentsOf: node.children)
                }
            }
        }
        if indices.count == originalIndices.count {
            indices = originalIndices
        } else {
            indices.sort()
        }
        return QueryResult(indices: indices, visitedNodeCount: visitedNodeCount,
                           examinedPointCount: examinedPointCount)
    }

    private static func searchBounds(for mapRect: MKMapRect) -> [Bounds] {
        guard mapRect.origin.x.isFinite, mapRect.origin.y.isFinite,
              mapRect.size.width.isFinite, mapRect.size.height.isFinite,
              mapRect.size.width >= 0, mapRect.size.height >= 0 else { return [] }
        let world = MKMapRect.world
        let minY = max(0, mapRect.origin.y)
        let maxY = min(world.size.height, mapRect.origin.y + mapRect.size.height)
        guard minY <= maxY else { return [] }
        let width = world.size.width
        if mapRect.size.width >= width {
            return [Bounds(minX: 0, maxX: width, minY: minY, maxY: maxY)]
        }
        var minX = mapRect.origin.x.truncatingRemainder(dividingBy: width)
        if minX < 0 { minX += width }
        let maxX = minX + mapRect.size.width
        if maxX < width {
            return [Bounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)]
        }
        // Include x = 0 even when the right edge lands exactly on the date line.
        return [Bounds(minX: minX, maxX: width, minY: minY, maxY: maxY),
                Bounds(minX: 0, maxX: maxX - width, minY: minY, maxY: maxY)]
    }

    private nonisolated struct Point: Sendable {
        let x: Double
        let y: Double
        let originalIndex: Int
    }

    private nonisolated struct Bounds: Sendable {
        let minX: Double
        let maxX: Double
        let minY: Double
        let maxY: Double

        func contains(_ point: Point) -> Bool {
            point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }

        func contains(_ other: Bounds) -> Bool {
            other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
        }

        func intersects(_ other: Bounds) -> Bool {
            other.maxX >= minX && other.minX <= maxX && other.maxY >= minY && other.minY <= maxY
        }
    }

    private nonisolated struct Node: Sendable {
        let bounds: Bounds
        let pointRange: Range<Int>
        let children: [Int]
    }

    /// Tight bounds prune empty space. Contiguous subtree ranges make a fully included
    /// node output proportional to its results, without visiting its descendant nodes.
    private nonisolated struct Builder {
        private static let leafCapacity = 16
        private static let maximumDepth = 24
        var points: [Point] = []
        var nodes: [Node] = []

        @discardableResult
        mutating func append(_ entries: [Point], depth: Int) -> Int {
            guard !_Concurrency.Task.isCancelled else { return -1 }
            var minX = entries[0].x
            var maxX = minX
            var minY = entries[0].y
            var maxY = minY
            for (offset, point) in entries.dropFirst().enumerated() {
                if offset.isMultiple(of: 128), _Concurrency.Task.isCancelled { return -1 }
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            let bounds = Bounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
            let start = points.count
            let nodeIndex = nodes.count
            nodes.append(Node(bounds: bounds, pointRange: start..<start, children: []))
            var children: [Int] = []
            if entries.count > Self.leafCapacity, depth < Self.maximumDepth,
               minX != maxX || minY != maxY {
                let midX = minX + (maxX - minX) / 2
                let midY = minY + (maxY - minY) / 2
                var quadrants = Array(repeating: [Point](), count: 4)
                for (offset, point) in entries.enumerated() {
                    if offset.isMultiple(of: 128), _Concurrency.Task.isCancelled { return -1 }
                    let quadrant = (point.x >= midX ? 1 : 0) + (point.y >= midY ? 2 : 0)
                    quadrants[quadrant].append(point)
                }
                let occupied = quadrants.filter { !$0.isEmpty }
                // A numerically indivisible range or duplicate coordinates remain one
                // leaf, avoiding repeated subdivision of large same-location datasets.
                if occupied.count > 1 {
                    children = occupied.map { append($0, depth: depth + 1) }
                }
            }
            if children.isEmpty { points.append(contentsOf: entries) }
            nodes[nodeIndex] = Node(bounds: bounds, pointRange: start..<points.count, children: children)
            return nodeIndex
        }
    }
}
