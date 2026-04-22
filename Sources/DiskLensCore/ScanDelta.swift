import Foundation

public struct ScanDelta: Codable, Equatable, Sendable {
    public var newItems: [DeltaEntry]
    public var grownItems: [DeltaEntry]
    public var shrunkItems: [DeltaEntry]
    public var removedItems: [DeltaEntry]

    public var hasChanges: Bool {
        !newItems.isEmpty || !grownItems.isEmpty || !shrunkItems.isEmpty || !removedItems.isEmpty
    }

    public var totalChangeCount: Int {
        newItems.count + grownItems.count + shrunkItems.count + removedItems.count
    }

    public init(
        newItems: [DeltaEntry] = [],
        grownItems: [DeltaEntry] = [],
        shrunkItems: [DeltaEntry] = [],
        removedItems: [DeltaEntry] = []
    ) {
        self.newItems = newItems
        self.grownItems = grownItems
        self.shrunkItems = shrunkItems
        self.removedItems = removedItems
    }
}

public struct DeltaEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var oldSizeBytes: Int64?
    public var newSizeBytes: Int64?
    public var changePercent: Double
    public var category: ItemCategory
    public var risk: RiskLevel

    public init(
        path: String,
        name: String,
        oldSizeBytes: Int64?,
        newSizeBytes: Int64?,
        changePercent: Double,
        category: ItemCategory,
        risk: RiskLevel
    ) {
        self.path = path
        self.name = name
        self.oldSizeBytes = oldSizeBytes
        self.newSizeBytes = newSizeBytes
        self.changePercent = changePercent
        self.category = category
        self.risk = risk
    }
}
