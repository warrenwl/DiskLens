import Foundation

public struct ScanOptions: Sendable {
    public var mode: ScanMode
    public var customRoots: [URL]
    public var maxDisplayDepth: Int
    public var maxChildrenPerNode: Int

    public init(
        mode: ScanMode,
        customRoots: [URL] = [],
        maxDisplayDepth: Int = 3,
        maxChildrenPerNode: Int = 120
    ) {
        self.mode = mode
        self.customRoots = customRoots
        self.maxDisplayDepth = maxDisplayDepth
        self.maxChildrenPerNode = maxChildrenPerNode
    }
}

public struct DirectoryLevelResult: Sendable {
    public var item: ScanItem
    public var inaccessiblePaths: [String]

    public init(item: ScanItem, inaccessiblePaths: [String]) {
        self.item = item
        self.inaccessiblePaths = inaccessiblePaths
    }
}

public struct DiskScanner: Sendable {
    public init() {}

    public func scan(
        options: ScanOptions,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> ScanResult {
        let task = Task.detached(priority: .userInitiated) {
            Self.scanSync(options: options, onProgress: onProgress)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func scanDirectoryLevel(url: URL, parentPath: String? = nil) async -> DirectoryLevelResult {
        await Task.detached(priority: .userInitiated) {
            Self.scanDirectoryLevelSync(url: url, parentPath: parentPath)
        }.value
    }

    private static func scanSync(
        options: ScanOptions,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) -> ScanResult {
        let roots = roots(for: options)
        var scannedItems: [ScanItem] = []
        let progress = ScanProgressTracker(initialPath: roots.first?.path ?? "", onProgress: onProgress)

        progress.emit(force: true)

        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            if Task.isCancelled { break }
            progress.setCurrentPath(root.path)
            progress.emit(force: true)
            let result = scanDirectoryLevelSync(url: root, parentPath: nil)
            progress.addBytes(result.item.sizeBytes)
            result.inaccessiblePaths.forEach { progress.recordInaccessible($0) }
            scannedItems.append(result.item)
            progress.emit(force: true)
        }
        progress.setCancelled(Task.isCancelled)
        progress.emit(force: true)

        scannedItems.sort { $0.sizeBytes > $1.sizeBytes }
        let scannedBytes = scannedItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let summary = makeSummary(
            mode: options.mode,
            roots: roots.map(\.path),
            scannedBytes: scannedBytes,
            inaccessiblePaths: progress.snapshot.inaccessiblePaths,
            startedAt: progress.snapshot.startedAt,
            isCancelled: progress.snapshot.isCancelled
        )
        let recommendations = RecommendationEngine.recommendations(from: scannedItems)

        return ScanResult(summary: summary, items: scannedItems, recommendations: recommendations)
    }

    private static func roots(for options: ScanOptions) -> [URL] {
        switch options.mode {
        case .defaultScope:
            let home = FileManager.default.homeDirectoryForCurrentUser
            let focusedHomeRoots = [
                "ComfyUI",
                ".ollama",
                "ollama-models",
                "ai-models",
                ".cache",
                ".npm",
                ".gemini",
                "Downloads",
                "project",
                "study",
                "Library/Caches",
                "Library/Application Support",
                "Library/Containers/com.docker.docker",
                "Library/Containers/com.tencent.qq",
                "Library/Containers/com.tencent.xinWeChat",
            ].map { home.appendingPathComponent($0) }
            return (focusedHomeRoots + [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/Library"),
                URL(fileURLWithPath: "/opt/homebrew"),
            ])
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .deduplicatedByPath()
        case .dataVolume:
            return [URL(fileURLWithPath: "/System/Volumes/Data")]
        case .custom:
            return options.customRoots.deduplicatedByPath()
        }
    }

    private static func scanNode(
        _ url: URL,
        depth: Int,
        parentPath: String?,
        maxDisplayDepth: Int,
        maxChildrenPerNode: Int,
        progress: ScanProgressTracker
    ) -> (item: ScanItem, inaccessibleCount: Int) {
        let path = url.path
        let name = displayName(for: url)
        let kind = itemKind(for: url)
        var inaccessibleCount = kind == .inaccessible ? 1 : 0
        progress.setCurrentPath(path)
        switch kind {
        case .directory:
            progress.incrementDirectories()
        case .file, .symlink:
            progress.incrementFiles()
        case .inaccessible:
            progress.recordInaccessible(path)
        }
        progress.emit(force: false)

        if kind == .file || kind == .symlink || kind == .inaccessible {
            let bytes = allocatedSize(for: url)
            progress.addBytes(bytes)
            let classification = ClassificationRules.classify(path: path, kind: kind, sizeBytes: bytes)
            progress.emit(force: false)
            return (
                ScanItem(
                    path: path,
                    name: name,
                    sizeBytes: bytes,
                    depth: depth,
                    parentPath: parentPath,
                    kind: kind,
                    category: classification.category,
                    risk: classification.risk,
                    reclaimableBytes: Int64(Double(bytes) * classification.reclaimableRatio),
                    recommendedAction: classification.recommendedAction,
                    detail: classification.detail,
                    isReadable: kind != .inaccessible,
                    children: []
                ),
                inaccessibleCount
            )
        }

        let childrenURLs: [URL]
        do {
            childrenURLs = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: []
            )
        } catch {
            let bytes = allocatedSize(for: url)
            progress.addBytes(bytes)
            progress.recordInaccessible(path)
            let classification = ClassificationRules.classify(path: path, kind: .inaccessible, sizeBytes: bytes)
            progress.emit(force: false)
            return (
                ScanItem(
                    path: path,
                    name: name,
                    sizeBytes: bytes,
                    depth: depth,
                    parentPath: parentPath,
                    kind: .inaccessible,
                    category: classification.category,
                    risk: classification.risk,
                    reclaimableBytes: 0,
                    recommendedAction: classification.recommendedAction,
                    detail: "无法读取：\(error.localizedDescription)",
                    isReadable: false,
                    children: []
                ),
                inaccessibleCount + 1
            )
        }

        var childItems: [ScanItem] = []
        var totalBytes = allocatedSize(for: url)

        for childURL in childrenURLs {
            if Task.isCancelled { break }
            let child = scanNode(
                childURL,
                depth: depth + 1,
                parentPath: path,
                maxDisplayDepth: maxDisplayDepth,
                maxChildrenPerNode: maxChildrenPerNode,
                progress: progress
            )
            inaccessibleCount += child.inaccessibleCount
            totalBytes += child.item.sizeBytes
            if depth < maxDisplayDepth {
                childItems.append(child.item)
            }
        }

        childItems.sort { lhs, rhs in
            if lhs.sizeBytes == rhs.sizeBytes { return lhs.name < rhs.name }
            return lhs.sizeBytes > rhs.sizeBytes
        }
        if childItems.count > maxChildrenPerNode {
            childItems = Array(childItems.prefix(maxChildrenPerNode))
        }

        let classification = ClassificationRules.classify(path: path, kind: .directory, sizeBytes: totalBytes)
        return (
            ScanItem(
                path: path,
                name: name,
                sizeBytes: totalBytes,
                depth: depth,
                parentPath: parentPath,
                kind: .directory,
                category: classification.category,
                risk: classification.risk,
                reclaimableBytes: Int64(Double(totalBytes) * classification.reclaimableRatio),
                recommendedAction: classification.recommendedAction,
                detail: classification.detail,
                isReadable: true,
                children: childItems
            ),
            inaccessibleCount
        )
    }

    private static func itemKind(for url: URL) -> ItemKind {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isReadableKey])
            if values.isSymbolicLink == true {
                return .symlink
            }
            if values.isReadable == false {
                return .inaccessible
            }
            return values.isDirectory == true ? .directory : .file
        } catch {
            return .inaccessible
        }
    }

    private static func allocatedSize(for url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            if let total = values.totalFileAllocatedSize {
                return Int64(total)
            }
            if let file = values.fileAllocatedSize {
                return Int64(file)
            }
        } catch {
            return 0
        }
        return 0
    }

    private static func makeSummary(
        mode: ScanMode,
        roots: [String],
        scannedBytes: Int64,
        inaccessiblePaths: [String],
        startedAt: Date,
        isCancelled: Bool
    ) -> ScanSummary {
        let rootStats = fileSystemStats(for: "/")
        let dataStats = fileSystemStats(for: "/System/Volumes/Data")
        let systemUsed = max(rootStats.usedBytes - dataStats.usedBytes, 0)
        let now = Date()
        return ScanSummary(
            totalBytes: rootStats.totalBytes,
            usedBytes: rootStats.usedBytes,
            availableBytes: rootStats.availableBytes,
            dataVolumeBytes: dataStats.usedBytes,
            systemVolumeBytes: systemUsed,
            scannedBytes: scannedBytes,
            scannedAt: now,
            mode: mode,
            roots: roots,
            inaccessibleCount: inaccessiblePaths.count,
            inaccessiblePaths: Array(inaccessiblePaths.prefix(200)),
            scanDurationSeconds: now.timeIntervalSince(startedAt),
            isCancelled: isCancelled
        )
    }

    private static func fileSystemStats(for path: String) -> (totalBytes: Int64, availableBytes: Int64, usedBytes: Int64) {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            let total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            return (total, free, max(total - free, 0))
        } catch {
            return (0, 0, 0)
        }
    }

    private static func displayName(for url: URL) -> String {
        let path = url.path
        if path == FileManager.default.homeDirectoryForCurrentUser.path {
            return "~"
        }
        if path == "/" {
            return "/"
        }
        return url.lastPathComponent.isEmpty ? path : url.lastPathComponent
    }

    private static func scanDirectoryLevelSync(url: URL, parentPath: String?) -> DirectoryLevelResult {
        var inaccessiblePaths: [String] = []
        let rootPath = url.path
        let kind = itemKind(for: url)

        if kind != .directory {
            let bytes = allocatedSize(for: url)
            let classification = ClassificationRules.classify(path: rootPath, kind: kind, sizeBytes: bytes)
            return DirectoryLevelResult(
                item: ScanItem(
                    path: rootPath,
                    name: displayName(for: url),
                    sizeBytes: bytes,
                    depth: parentPath == nil ? 0 : 1,
                    parentPath: parentPath,
                    kind: kind,
                    category: classification.category,
                    risk: classification.risk,
                    reclaimableBytes: Int64(Double(bytes) * classification.reclaimableRatio),
                    recommendedAction: classification.recommendedAction,
                    detail: classification.detail,
                    isReadable: kind != .inaccessible,
                    children: []
                ),
                inaccessiblePaths: kind == .inaccessible ? [rootPath] : []
            )
        }

        if let duResult = duDirectoryLevel(url: url, parentPath: parentPath) {
            return duResult
        }

        do {
            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsPackageDescendants]
            )
            var childItems = children.map { childURL in
                shallowItem(for: childURL, parentPath: rootPath)
            }
            childItems.sort { lhs, rhs in
                if lhs.sizeBytes == rhs.sizeBytes { return lhs.name < rhs.name }
                return lhs.sizeBytes > rhs.sizeBytes
            }
            let total = childItems.reduce(allocatedSize(for: url)) { $0 + $1.sizeBytes }
            let classification = ClassificationRules.classify(path: rootPath, kind: .directory, sizeBytes: total)
            return DirectoryLevelResult(
                item: ScanItem(
                    path: rootPath,
                    name: displayName(for: url),
                    sizeBytes: total,
                    depth: parentPath == nil ? 0 : 1,
                    parentPath: parentPath,
                    kind: .directory,
                    category: classification.category,
                    risk: classification.risk,
                    reclaimableBytes: Int64(Double(total) * classification.reclaimableRatio),
                    recommendedAction: classification.recommendedAction,
                    detail: classification.detail,
                    isReadable: true,
                    children: Array(childItems.prefix(120))
                ),
                inaccessiblePaths: inaccessiblePaths
            )
        } catch {
            inaccessiblePaths.append(rootPath)
            let classification = ClassificationRules.classify(path: rootPath, kind: .inaccessible, sizeBytes: 0)
            return DirectoryLevelResult(
                item: ScanItem(
                    path: rootPath,
                    name: displayName(for: url),
                    sizeBytes: 0,
                    depth: parentPath == nil ? 0 : 1,
                    parentPath: parentPath,
                    kind: .inaccessible,
                    category: classification.category,
                    risk: classification.risk,
                    reclaimableBytes: 0,
                    recommendedAction: classification.recommendedAction,
                    detail: "无法读取：\(error.localizedDescription)",
                    isReadable: false,
                    children: []
                ),
                inaccessiblePaths: inaccessiblePaths
            )
        }
    }

    private static func shallowItem(for url: URL, parentPath: String) -> ScanItem {
        let kind = itemKind(for: url)
        let bytes = allocatedSize(for: url)
        let classification = ClassificationRules.classify(path: url.path, kind: kind, sizeBytes: bytes)
        return ScanItem(
            path: url.path,
            name: displayName(for: url),
            sizeBytes: bytes,
            depth: 1,
            parentPath: parentPath,
            kind: kind,
            category: classification.category,
            risk: classification.risk,
            reclaimableBytes: Int64(Double(bytes) * classification.reclaimableRatio),
            recommendedAction: classification.recommendedAction,
            detail: classification.detail,
            isReadable: kind != .inaccessible,
            children: []
        )
    }

    private static func duDirectoryLevel(url: URL, parentPath: String?) -> DirectoryLevelResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-x", "-k", "-d", "1", url.path]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return nil
        }

        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let inaccessible = String(data: errorData, encoding: .utf8)?
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.contains("Operation not permitted") || line.contains("Permission denied") else { return nil }
                let raw = line.split(separator: ":", maxSplits: 2).dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
                return raw?.isEmpty == false ? raw : nil
            } ?? []

        var sizes: [(path: String, bytes: Int64)] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let kib = Int64(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            sizes.append((String(parts[1]), kib * 1024))
        }

        guard let rootEntry = sizes.first(where: { $0.path == url.path }) ?? sizes.last else {
            return nil
        }

        let childItems = sizes
            .filter { $0.path != url.path }
            .map { entry in
                itemFromDu(path: entry.path, bytes: entry.bytes, parentPath: url.path)
            }
            .sorted { lhs, rhs in
                if lhs.sizeBytes == rhs.sizeBytes { return lhs.name < rhs.name }
                return lhs.sizeBytes > rhs.sizeBytes
            }

        let classification = ClassificationRules.classify(path: url.path, kind: .directory, sizeBytes: rootEntry.bytes)
        let root = ScanItem(
            path: url.path,
            name: displayName(for: url),
            sizeBytes: rootEntry.bytes,
            depth: parentPath == nil ? 0 : 1,
            parentPath: parentPath,
            kind: .directory,
            category: classification.category,
            risk: classification.risk,
            reclaimableBytes: Int64(Double(rootEntry.bytes) * classification.reclaimableRatio),
            recommendedAction: classification.recommendedAction,
            detail: classification.detail,
            isReadable: true,
            children: Array(childItems.prefix(120))
        )
        return DirectoryLevelResult(item: root, inaccessiblePaths: inaccessible)
    }

    private static func itemFromDu(path: String, bytes: Int64, parentPath: String) -> ScanItem {
        let url = URL(fileURLWithPath: path)
        let kind = itemKind(for: url)
        let classification = ClassificationRules.classify(path: path, kind: kind, sizeBytes: bytes)
        return ScanItem(
            path: path,
            name: displayName(for: url),
            sizeBytes: bytes,
            depth: 1,
            parentPath: parentPath,
            kind: kind,
            category: classification.category,
            risk: classification.risk,
            reclaimableBytes: Int64(Double(bytes) * classification.reclaimableRatio),
            recommendedAction: classification.recommendedAction,
            detail: classification.detail,
            isReadable: kind != .inaccessible,
            children: []
        )
    }
}

private let resourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .isReadableKey,
    .totalFileAllocatedSizeKey,
    .fileAllocatedSizeKey,
]

private final class ScanProgressTracker: @unchecked Sendable {
    private var progress: ScanProgress
    private var lastEmit = Date.distantPast
    private let onProgress: (@Sendable (ScanProgress) -> Void)?

    init(initialPath: String, onProgress: (@Sendable (ScanProgress) -> Void)?) {
        self.progress = ScanProgress(
            currentPath: initialPath,
            scannedDirectories: 0,
            scannedFiles: 0,
            scannedBytes: 0,
            inaccessiblePaths: [],
            startedAt: Date(),
            updatedAt: Date(),
            isCancelled: false
        )
        self.onProgress = onProgress
    }

    var snapshot: ScanProgress {
        progress
    }

    func setCurrentPath(_ path: String) {
        progress.currentPath = path
    }

    func incrementDirectories() {
        progress.scannedDirectories += 1
    }

    func incrementFiles() {
        progress.scannedFiles += 1
    }

    func addBytes(_ bytes: Int64) {
        progress.scannedBytes += bytes
    }

    func recordInaccessible(_ path: String) {
        if progress.inaccessiblePaths.last != path {
            progress.inaccessiblePaths.append(path)
        }
    }

    func setCancelled(_ isCancelled: Bool) {
        progress.isCancelled = isCancelled
    }

    func emit(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastEmit) >= 0.2 else { return }
        lastEmit = now
        progress.updatedAt = now
        progress.isCancelled = Task.isCancelled
        onProgress?(progress)
    }
}

private extension Array where Element == URL {
    func deduplicatedByPath() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}
