import Foundation

public struct ScanTreeIndex: Sendable {
    public let roots: [ScanItem]
    public private(set) var flatItems: [ScanItem] = []

    private var itemsByPath: [String: ScanItem] = [:]

    public init(roots: [ScanItem]) {
        self.roots = roots
        for root in roots {
            append(root)
        }
    }

    public func find(path: String) -> ScanItem? {
        itemsByPath[path]
    }

    public func treemapItems(rootPath: String?) -> [ScanItem] {
        guard let rootPath, let root = find(path: rootPath) else {
            return roots
        }
        return root.children
    }

    public func breadcrumbs(rootPath: String?) -> [(label: String, path: String?)] {
        guard let rootPath, let item = find(path: rootPath) else {
            return [("扫描结果", nil)]
        }
        var chain: [ScanItem] = [item]
        var parent = item.parentPath
        while let parentPath = parent, let parentItem = find(path: parentPath) {
            chain.append(parentItem)
            parent = parentItem.parentPath
        }
        return [("扫描结果", nil)] + chain.reversed().map { ($0.name, Optional($0.path)) }
    }

    private mutating func append(_ item: ScanItem) {
        flatItems.append(item)
        itemsByPath[item.path] = item
        for child in item.children {
            append(child)
        }
    }
}

public enum ScanTree {
    public static func find(path: String, in roots: [ScanItem]) -> ScanItem? {
        ScanTreeIndex(roots: roots).find(path: path)
    }

    public static func treemapItems(roots: [ScanItem], rootPath: String?) -> [ScanItem] {
        ScanTreeIndex(roots: roots).treemapItems(rootPath: rootPath)
    }

    public static func breadcrumbs(rootPath: String?, roots: [ScanItem]) -> [(label: String, path: String?)] {
        ScanTreeIndex(roots: roots).breadcrumbs(rootPath: rootPath)
    }
}
