import Foundation

public enum ScanMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case defaultScope
    case dataVolume
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .defaultScope:
            return "重点目录"
        case .dataVolume:
            return "全 Data 卷"
        case .custom:
            return "手动选择目录"
        }
    }
}

public enum ItemCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case aiModel
    case cache
    case developerBuild
    case docker
    case application
    case userData
    case protectedData
    case systemData
    case unknown

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .aiModel: return "AI/模型"
        case .cache: return "可重建缓存"
        case .developerBuild: return "开发构建产物"
        case .docker: return "Docker 数据"
        case .application: return "应用程序"
        case .userData: return "用户文件"
        case .protectedData: return "敏感/应用数据"
        case .systemData: return "系统相关"
        case .unknown: return "未分类"
        }
    }
}

public enum RiskLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case safeClean
    case review
    case keep
    case system

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .safeClean: return "可安全清理"
        case .review: return "谨慎清理"
        case .keep: return "建议保留"
        case .system: return "系统相关"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .safeClean: return 0
        case .review: return 1
        case .keep: return 2
        case .system: return 3
        }
    }
}

public enum ItemKind: String, Codable, Sendable {
    case file
    case directory
    case symlink
    case inaccessible
}

public struct ScanProgress: Codable, Equatable, Sendable {
    public var currentPath: String
    public var scannedDirectories: Int
    public var scannedFiles: Int
    public var scannedBytes: Int64
    public var inaccessiblePaths: [String]
    public var startedAt: Date
    public var updatedAt: Date
    public var isCancelled: Bool

    public init(
        currentPath: String,
        scannedDirectories: Int,
        scannedFiles: Int,
        scannedBytes: Int64,
        inaccessiblePaths: [String],
        startedAt: Date,
        updatedAt: Date,
        isCancelled: Bool
    ) {
        self.currentPath = currentPath
        self.scannedDirectories = scannedDirectories
        self.scannedFiles = scannedFiles
        self.scannedBytes = scannedBytes
        self.inaccessiblePaths = inaccessiblePaths
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.isCancelled = isCancelled
    }

    public var elapsedSeconds: TimeInterval {
        updatedAt.timeIntervalSince(startedAt)
    }
}

public struct ScanSummary: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var totalBytes: Int64
    public var usedBytes: Int64
    public var availableBytes: Int64
    public var dataVolumeBytes: Int64
    public var systemVolumeBytes: Int64
    public var scannedBytes: Int64
    public var scannedAt: Date
    public var mode: ScanMode
    public var roots: [String]
    public var inaccessibleCount: Int
    public var inaccessiblePaths: [String]
    public var scanDurationSeconds: TimeInterval
    public var isCancelled: Bool

    public init(
        schemaVersion: Int = 1,
        totalBytes: Int64,
        usedBytes: Int64,
        availableBytes: Int64,
        dataVolumeBytes: Int64,
        systemVolumeBytes: Int64,
        scannedBytes: Int64,
        scannedAt: Date,
        mode: ScanMode,
        roots: [String],
        inaccessibleCount: Int,
        inaccessiblePaths: [String] = [],
        scanDurationSeconds: TimeInterval = 0,
        isCancelled: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.dataVolumeBytes = dataVolumeBytes
        self.systemVolumeBytes = systemVolumeBytes
        self.scannedBytes = scannedBytes
        self.scannedAt = scannedAt
        self.mode = mode
        self.roots = roots
        self.inaccessibleCount = inaccessibleCount
        self.inaccessiblePaths = inaccessiblePaths
        self.scanDurationSeconds = scanDurationSeconds
        self.isCancelled = isCancelled
    }
}

public struct ScanItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var sizeBytes: Int64
    public var depth: Int
    public var parentPath: String?
    public var kind: ItemKind
    public var category: ItemCategory
    public var risk: RiskLevel
    public var reclaimableBytes: Int64
    public var recommendedAction: String
    public var detail: String
    public var isReadable: Bool
    public var children: [ScanItem]

    public init(
        path: String,
        name: String,
        sizeBytes: Int64,
        depth: Int,
        parentPath: String?,
        kind: ItemKind,
        category: ItemCategory,
        risk: RiskLevel,
        reclaimableBytes: Int64,
        recommendedAction: String,
        detail: String,
        isReadable: Bool,
        children: [ScanItem]
    ) {
        self.path = path
        self.name = name
        self.sizeBytes = sizeBytes
        self.depth = depth
        self.parentPath = parentPath
        self.kind = kind
        self.category = category
        self.risk = risk
        self.reclaimableBytes = reclaimableBytes
        self.recommendedAction = recommendedAction
        self.detail = detail
        self.isReadable = isReadable
        self.children = children
    }
}

public struct Recommendation: Codable, Identifiable, Equatable, Sendable {
    public var id: String { title + affectedPath }
    public var title: String
    public var affectedPath: String
    public var estimatedBytes: Int64
    public var risk: RiskLevel
    public var command: String?
    public var steps: String
    public var rationale: String

    public init(
        title: String,
        affectedPath: String,
        estimatedBytes: Int64,
        risk: RiskLevel,
        command: String?,
        steps: String,
        rationale: String = ""
    ) {
        self.title = title
        self.affectedPath = affectedPath
        self.estimatedBytes = estimatedBytes
        self.risk = risk
        self.command = command
        self.steps = steps
        self.rationale = rationale
    }
}

public struct ScanResult: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var summary: ScanSummary
    public var items: [ScanItem]
    public var recommendations: [Recommendation]

    public init(schemaVersion: Int = 1, summary: ScanSummary, items: [ScanItem], recommendations: [Recommendation]) {
        self.schemaVersion = schemaVersion
        self.summary = summary
        self.items = items
        self.recommendations = recommendations
    }
}

public enum RiskFilter: String, CaseIterable, Identifiable {
    case all
    case safeClean
    case review
    case keep
    case system

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "全部"
        case .safeClean: return RiskLevel.safeClean.label
        case .review: return RiskLevel.review.label
        case .keep: return RiskLevel.keep.label
        case .system: return RiskLevel.system.label
        }
    }

    public func includes(_ risk: RiskLevel) -> Bool {
        switch self {
        case .all: return true
        case .safeClean: return risk == .safeClean
        case .review: return risk == .review
        case .keep: return risk == .keep
        case .system: return risk == .system
        }
    }
}

public enum SizeThreshold: String, CaseIterable, Identifiable, Sendable {
    case all
    case over100MB
    case over1GB
    case over5GB
    case over10GB

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "全部大小"
        case .over100MB: return ">100 MB"
        case .over1GB: return ">1 GB"
        case .over5GB: return ">5 GB"
        case .over10GB: return ">10 GB"
        }
    }

    public var minimumBytes: Int64 {
        switch self {
        case .all: return 0
        case .over100MB: return 100_000_000
        case .over1GB: return 1_000_000_000
        case .over5GB: return 5_000_000_000
        case .over10GB: return 10_000_000_000
        }
    }
}

public enum ItemSortOption: String, CaseIterable, Identifiable, Sendable {
    case size
    case risk
    case category
    case path

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .size: return "按大小"
        case .risk: return "按风险"
        case .category: return "按分类"
        case .path: return "按路径"
        }
    }
}

public enum ScanItemFilter {
    public static func filter(
        items: [ScanItem],
        riskFilter: RiskFilter,
        selectedPath: String?,
        query: String,
        sizeThreshold: SizeThreshold,
        sort: ItemSortOption
    ) -> [ScanItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items
            .filter { $0.sizeBytes > 0 }
            .filter { riskFilter.includes($0.risk) }
            .filter { $0.sizeBytes >= sizeThreshold.minimumBytes }
            .filter { item in
                guard let selectedPath else { return true }
                return item.path == selectedPath || item.path.hasPrefix(selectedPath + "/")
            }
            .filter { item in
                guard !normalizedQuery.isEmpty else { return true }
                return item.path.lowercased().contains(normalizedQuery) ||
                    item.name.lowercased().contains(normalizedQuery) ||
                    item.category.label.lowercased().contains(normalizedQuery) ||
                    item.risk.label.lowercased().contains(normalizedQuery) ||
                    item.recommendedAction.lowercased().contains(normalizedQuery) ||
                    item.detail.lowercased().contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                switch sort {
                case .size:
                    if lhs.sizeBytes == rhs.sizeBytes { return lhs.path < rhs.path }
                    return lhs.sizeBytes > rhs.sizeBytes
                case .risk:
                    if lhs.risk.sortOrder == rhs.risk.sortOrder {
                        return lhs.sizeBytes > rhs.sizeBytes
                    }
                    return lhs.risk.sortOrder < rhs.risk.sortOrder
                case .category:
                    if lhs.category.label == rhs.category.label {
                        return lhs.sizeBytes > rhs.sizeBytes
                    }
                    return lhs.category.label < rhs.category.label
                case .path:
                    return lhs.path < rhs.path
                }
            }
    }
}
