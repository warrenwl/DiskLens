import Foundation

public enum ScanTree {
    public static func find(path: String, in roots: [ScanItem]) -> ScanItem? {
        for root in roots {
            if let found = find(path: path, in: root) {
                return found
            }
        }
        return nil
    }

    public static func treemapItems(roots: [ScanItem], rootPath: String?) -> [ScanItem] {
        guard let rootPath, let root = find(path: rootPath, in: roots) else {
            return roots
        }
        return root.children
    }

    public static func breadcrumbs(rootPath: String?, roots: [ScanItem]) -> [(label: String, path: String?)] {
        guard let rootPath, let item = find(path: rootPath, in: roots) else {
            return [("扫描结果", nil)]
        }
        var chain: [ScanItem] = [item]
        var parent = item.parentPath
        while let parentPath = parent, let parentItem = find(path: parentPath, in: roots) {
            chain.append(parentItem)
            parent = parentItem.parentPath
        }
        return [("扫描结果", nil)] + chain.reversed().map { ($0.name, Optional($0.path)) }
    }

    private static func find(path: String, in item: ScanItem) -> ScanItem? {
        if item.path == path {
            return item
        }
        for child in item.children {
            if let found = find(path: path, in: child) {
                return found
            }
        }
        return nil
    }
}
