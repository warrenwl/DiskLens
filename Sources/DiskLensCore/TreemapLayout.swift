import Foundation

public struct TreemapRect: Codable, Equatable, Sendable {
    public var item: ScanItem
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(item: ScanItem, x: Double, y: Double, width: Double, height: Double) {
        self.item = item
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum TreemapLayout {
    public static func layout(items: [ScanItem], width: Double, height: Double) -> [TreemapRect] {
        layout(items: items, x: 0, y: 0, width: width, height: height)
    }

    public static func layout(
        items: [ScanItem],
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> [TreemapRect] {
        let visible = items.filter { $0.sizeBytes > 0 }.sorted { $0.sizeBytes > $1.sizeBytes }
        let total = visible.reduce(Int64(0)) { $0 + $1.sizeBytes }
        guard total > 0, width > 0, height > 0 else { return [] }

        let scale = (width * height) / Double(total)
        var weighted = visible.map { WeightedItem(item: $0, area: Double($0.sizeBytes) * scale) }
        var remaining = Rect(x: x, y: y, width: width, height: height)
        var rects: [TreemapRect] = []

        while !weighted.isEmpty {
            var row: [WeightedItem] = []
            var rest = weighted
            let side = min(remaining.width, remaining.height)

            while let next = rest.first {
                if row.isEmpty || worst(row + [next], side: side) <= worst(row, side: side) {
                    row.append(next)
                    rest.removeFirst()
                } else {
                    break
                }
            }
            weighted = rest
            let laidOut = layout(row: row, in: remaining)
            rects.append(contentsOf: laidOut.map {
                TreemapRect(item: $0.item, x: $0.rect.x, y: $0.rect.y, width: $0.rect.width, height: $0.rect.height)
            })
            remaining = remaining.afterRemoving(rowArea: row.reduce(0) { $0 + $1.area })
        }

        return rects
    }

    public static func layout(
        items: [ScanItem],
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        horizontal: Bool
    ) -> [TreemapRect] {
        layout(items: items, x: x, y: y, width: width, height: height)
    }

    private static func worst(_ row: [WeightedItem], side: Double) -> Double {
        guard !row.isEmpty, side > 0 else { return .infinity }
        let areas = row.map(\.area)
        let sum = areas.reduce(0, +)
        guard let minArea = areas.min(), let maxArea = areas.max(), minArea > 0, sum > 0 else {
            return .infinity
        }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * maxArea / sumSquared, sumSquared / (sideSquared * minArea))
    }

    private static func layout(row: [WeightedItem], in rect: Rect) -> [(item: ScanItem, rect: Rect)] {
        let rowArea = row.reduce(0) { $0 + $1.area }
        guard rowArea > 0, rect.width > 0, rect.height > 0 else { return [] }

        if rect.width >= rect.height {
            let rowWidth = min(rowArea / rect.height, rect.width)
            var y = rect.y
            return row.map { weighted in
                let itemHeight = weighted.area / max(rowWidth, 1)
                defer { y += itemHeight }
                return (weighted.item, Rect(x: rect.x, y: y, width: rowWidth, height: itemHeight))
            }
        } else {
            let rowHeight = min(rowArea / rect.width, rect.height)
            var x = rect.x
            return row.map { weighted in
                let itemWidth = weighted.area / max(rowHeight, 1)
                defer { x += itemWidth }
                return (weighted.item, Rect(x: x, y: rect.y, width: itemWidth, height: rowHeight))
            }
        }
    }
}

private struct WeightedItem {
    var item: ScanItem
    var area: Double
}

private struct Rect {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    func afterRemoving(rowArea: Double) -> Rect {
        guard rowArea > 0, width > 0, height > 0 else { return self }
        if width >= height {
            let removedWidth = min(rowArea / height, width)
            return Rect(x: x + removedWidth, y: y, width: max(width - removedWidth, 0), height: height)
        } else {
            let removedHeight = min(rowArea / width, height)
            return Rect(x: x, y: y + removedHeight, width: width, height: max(height - removedHeight, 0))
        }
    }
}
