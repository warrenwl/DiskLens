import Foundation

public struct ScanOptions: Sendable {
    public var mode: ScanMode
    public var customRoots: [URL]
    public var maxChildrenPerNode: Int

    public init(
        mode: ScanMode,
        customRoots: [URL] = [],
        maxChildrenPerNode: Int = 120
    ) {
        self.mode = mode
        self.customRoots = customRoots
        self.maxChildrenPerNode = maxChildrenPerNode
    }
}

public struct DirectoryLevelResult: Sendable {
    public var item: ScanItem
    public var inaccessiblePaths: [String]
    public var scannedDirectories: Int
    public var scannedFiles: Int

    public init(
        item: ScanItem,
        inaccessiblePaths: [String],
        scannedDirectories: Int = 0,
        scannedFiles: Int = 0
    ) {
        self.item = item
        self.inaccessiblePaths = inaccessiblePaths
        self.scannedDirectories = scannedDirectories
        self.scannedFiles = scannedFiles
    }
}

public struct DiskScanner: Sendable {
    private static let duTimeoutSeconds: TimeInterval = 20

    public init() {}

    public func scan(
        options: ScanOptions,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> ScanResult {
        await Self.scanSync(options: options, onProgress: onProgress)
    }

    public func scanDirectoryLevel(
        url: URL,
        parentPath: String? = nil,
        maxChildrenPerNode: Int = 120
    ) async -> DirectoryLevelResult {
        await Task.detached(priority: .userInitiated) {
            Self.scanDirectoryLevelSync(
                url: url,
                parentPath: parentPath,
                maxChildrenPerNode: maxChildrenPerNode
            )
        }.value
    }

    private static func scanSync(
        options: ScanOptions,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) async -> ScanResult {
        let roots = roots(for: options)
        var scannedItems: [ScanItem] = []
        let progress = ScanProgressTracker(initialPath: roots.first?.path ?? "", onProgress: onProgress)

        progress.emit(force: true)

        await withTaskGroup(of: ScanItem?.self) { group in
            for root in roots {
                guard FileManager.default.fileExists(atPath: root.path) else { continue }
                group.addTask {
                    if Task.isCancelled { return nil }
                    progress.setPhase(.estimating)
                    progress.setCurrentPath(root.path)
                    progress.emit(force: true)
                    let result = scanDirectoryLevelSync(
                        url: root,
                        parentPath: nil,
                        maxChildrenPerNode: options.maxChildrenPerNode
                    )
                    progress.addBytes(result.item.sizeBytes)
                    progress.addMeasured(directories: result.scannedDirectories, files: result.scannedFiles)
                    for p in result.inaccessiblePaths { progress.recordInaccessible(p) }
                    progress.emit(force: true)
                    return result.item
                }
            }
            for await item in group {
                if let item { scannedItems.append(item) }
            }
        }

        progress.setPhase(.finalizing)
        progress.setCancelled(Task.isCancelled)
        progress.emit(force: true)

        scannedItems.sort { $0.sizeBytes > $1.sizeBytes }
        let scannedBytes = scannedItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let snap = progress.snapshot
        let summary = makeSummary(
            mode: options.mode,
            roots: roots.map(\.path),
            scannedBytes: scannedBytes,
            inaccessiblePaths: snap.inaccessiblePaths,
            startedAt: snap.startedAt,
            isCancelled: snap.isCancelled
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

    private static func scanDirectoryLevelSync(
        url: URL,
        parentPath: String?,
        maxChildrenPerNode: Int = 120
    ) -> DirectoryLevelResult {
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
                    command: classification.command,
                    detail: classification.detail,
                    isReadable: kind != .inaccessible,
                    children: []
                ),
                inaccessiblePaths: kind == .inaccessible ? [rootPath] : [],
                scannedDirectories: 0,
                scannedFiles: kind == .file || kind == .symlink ? 1 : 0
            )
        }

        if let duResult = duDirectoryLevel(
            url: url,
            parentPath: parentPath,
            maxChildrenPerNode: maxChildrenPerNode
        ) {
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
            let measured = measuredCounts(rootKind: .directory, children: childItems)
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
                    command: classification.command,
                    detail: classification.detail,
                    isReadable: true,
                    children: Array(childItems.prefix(maxChildrenPerNode))
                ),
                inaccessiblePaths: inaccessiblePaths,
                scannedDirectories: measured.directories,
                scannedFiles: measured.files
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
                    command: classification.command,
                    detail: "无法读取：\(error.localizedDescription)",
                    isReadable: false,
                    children: []
                ),
                inaccessiblePaths: inaccessiblePaths,
                scannedDirectories: 0,
                scannedFiles: 0
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
            command: classification.command,
            detail: classification.detail,
            isReadable: kind != .inaccessible,
            children: []
        )
    }

    private static func measuredCounts(
        rootKind: ItemKind,
        children: [ScanItem]
    ) -> (directories: Int, files: Int) {
        let rootDirectories = rootKind == .directory ? 1 : 0
        return children.reduce((directories: rootDirectories, files: 0)) { partial, item in
            switch item.kind {
            case .directory:
                return (partial.directories + 1, partial.files)
            case .file, .symlink:
                return (partial.directories, partial.files + 1)
            case .inaccessible:
                return partial
            }
        }
    }

    private static func duDirectoryLevel(
        url: URL,
        parentPath: String?,
        maxChildrenPerNode: Int
    ) -> DirectoryLevelResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-x", "-k", "-d", "1", url.path]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            return nil
        }

        guard waitForDu(process, timeout: duTimeoutSeconds) else {
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

        let measured = measuredCounts(rootKind: .directory, children: childItems)
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
            command: classification.command,
            detail: classification.detail,
            isReadable: true,
            children: Array(childItems.prefix(maxChildrenPerNode))
        )
        return DirectoryLevelResult(
            item: root,
            inaccessiblePaths: inaccessible,
            scannedDirectories: measured.directories,
            scannedFiles: measured.files
        )
    }

    private static func waitForDu(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < terminationDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                return false
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
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
            command: classification.command,
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
    private let lock = NSLock()

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
        lock.lock()
        defer { lock.unlock() }
        return progress
    }

    func setCurrentPath(_ path: String) {
        lock.lock()
        progress.currentPath = path
        lock.unlock()
    }

    func setPhase(_ phase: ScanPhase) {
        lock.lock()
        progress.phase = phase
        lock.unlock()
    }

    func addMeasured(directories: Int, files: Int) {
        lock.lock()
        progress.scannedDirectories += directories
        progress.scannedFiles += files
        lock.unlock()
    }

    func addBytes(_ bytes: Int64) {
        lock.lock()
        progress.scannedBytes += bytes
        lock.unlock()
    }

    func recordInaccessible(_ path: String) {
        lock.lock()
        if progress.inaccessiblePaths.last != path {
            progress.inaccessiblePaths.append(path)
        }
        lock.unlock()
    }

    func setCancelled(_ isCancelled: Bool) {
        lock.lock()
        progress.isCancelled = isCancelled
        lock.unlock()
    }

    func emit(force: Bool) {
        lock.lock()
        let now = Date()
        guard force || now.timeIntervalSince(lastEmit) >= 0.2 else {
            lock.unlock()
            return
        }
        lastEmit = now
        progress.updatedAt = now
        progress.isCancelled = Task.isCancelled
        let snapshot = progress
        lock.unlock()
        onProgress?(snapshot)
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
