import DiskLensCore
import Foundation

@discardableResult
@MainActor
func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
    if !condition() {
        failures.append(message)
        print("FAIL: \(message)")
        return false
    }
    print("PASS: \(message)")
    return true
}

var failures: [String] = []

final class ProgressSink: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [ScanProgress] = []

    func append(_ progress: ScanProgress) {
        lock.lock()
        snapshots.append(progress)
        lock.unlock()
    }

    var last: ScanProgress? {
        lock.lock()
        defer { lock.unlock() }
        return snapshots.last
    }

    func containsPhase(_ phase: ScanPhase) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return snapshots.contains { $0.phase == phase }
    }
}

func makeItem(
    name: String,
    path: String? = nil,
    bytes: Int64,
    category: ItemCategory = .unknown,
    risk: RiskLevel = .review,
    parentPath: String? = nil,
    children: [ScanItem] = []
) -> ScanItem {
    ScanItem(
        path: path ?? "/tmp/\(name)",
        name: name,
        sizeBytes: bytes,
        depth: 0,
        parentPath: parentPath,
        kind: .directory,
        category: category,
        risk: risk,
        reclaimableBytes: 0,
        recommendedAction: "",
        detail: "",
        isReadable: true,
        children: children
    )
}

let comfy = ClassificationRules.classify(
    path: "/Users/warrn/ComfyUI/models/unet/qwen-image.gguf",
    kind: .file,
    sizeBytes: 20_000_000_000
)
expect(comfy.category == .aiModel, "ComfyUI model is classified as AI model")
expect(comfy.risk == .review, "ComfyUI model is review-only")

let npm = ClassificationRules.classify(
    path: "/Users/warrn/.npm/_cacache/content-v2",
    kind: .directory,
    sizeBytes: 5_000_000_000
)
expect(npm.category == .cache, "npm cache is classified as cache")
expect(npm.risk == .safeClean, "npm cache is safe-clean")
expect(npm.recommendedAction.contains("npm"), "npm cache exposes npm-specific action text")
expect(npm.command == "npm cache clean --force", "npm cache exposes structured safe command")

let container = ClassificationRules.classify(
    path: "/Users/warrn/Library/Containers/com.tencent.xinWeChat/Data",
    kind: .directory,
    sizeBytes: 2_000_000_000
)
expect(container.category == .protectedData, "chat container is protected data")
expect(container.risk == .keep, "chat container is keep")

let system = ClassificationRules.classify(
    path: "/private/var/folders",
    kind: .directory,
    sizeBytes: 8_000_000_000
)
expect(system.category == .systemData, "private var is system data")
expect(system.risk == .system, "private var is system risk")

let rects = TreemapLayout.layout(
    items: [makeItem(name: "A", bytes: 60), makeItem(name: "B", bytes: 30), makeItem(name: "C", bytes: 10)],
    width: 1000,
    height: 500
)
expect(rects.count == 3, "treemap keeps positive items")
let totalArea = rects.map { $0.width * $0.height }.reduce(0, +)
expect(abs(totalArea - 500_000) < 0.01, "treemap preserves total area")
let largestRect = rects.max { $0.width * $0.height < $1.width * $1.height }
expect(largestRect?.item.name == "A", "treemap gives largest area to largest item")

let progress = ScanProgress(
    currentPath: "/Users/warrn/ComfyUI",
    scannedDirectories: 12,
    scannedFiles: 34,
    scannedBytes: 56_000_000,
    inaccessiblePaths: ["/Users/warrn/Library/Mail"],
    startedAt: Date(timeIntervalSince1970: 0),
    updatedAt: Date(timeIntervalSince1970: 5),
    isCancelled: false
)
expect(progress.elapsedSeconds == 5, "scan progress exposes elapsed time")
expect(progress.phase == .preparing, "scan progress defaults to preparing phase")
expect(progress.inaccessiblePaths.first == "/Users/warrn/Library/Mail", "scan progress records inaccessible paths")

let filtered = ScanItemFilter.filter(
    items: [
        makeItem(name: "uv", path: "/Users/warrn/.cache/uv", bytes: 6_000_000_000, category: .cache, risk: .safeClean),
        makeItem(name: "notes", path: "/Users/warrn/Documents/notes", bytes: 10_000_000, category: .userData, risk: .keep),
    ],
    riskFilter: .safeClean,
    selectedPath: nil,
    query: "uv",
    sizeThreshold: .over1GB,
    sort: .size
)
expect(filtered.count == 1 && filtered[0].name == "uv", "search, risk and size threshold filter locate cache item")

let child = makeItem(name: "unet", path: "/Users/warrn/ComfyUI/models/unet", bytes: 100, parentPath: "/Users/warrn/ComfyUI")
let root = makeItem(name: "ComfyUI", path: "/Users/warrn/ComfyUI", bytes: 200, children: [child])
let index = ScanTreeIndex(roots: [root])
expect(index.flatItems.map(\.path) == [root.path, child.path], "scan tree index preserves flattened pre-order")
expect(index.find(path: child.path)?.name == "unet", "scan tree index finds items by path")
expect(index.treemapItems(rootPath: root.path).first?.name == "unet", "scan tree index returns children for treemap root")
expect(index.breadcrumbs(rootPath: child.path).map(\.label).contains("unet"), "scan tree index builds breadcrumbs")
expect(ScanTree.treemapItems(roots: [root], rootPath: "/Users/warrn/ComfyUI").first?.name == "unet", "treemap navigation returns child items for drilled root")
expect(ScanTree.breadcrumbs(rootPath: "/Users/warrn/ComfyUI/models/unet", roots: [root]).map(\.label).contains("unet"), "treemap breadcrumbs include drilled item")

let recommendations = [
    Recommendation(
        title: "ComfyUI",
        affectedPath: "/Users/warrn/ComfyUI/models/unet",
        estimatedBytes: 100,
        risk: .review,
        command: nil,
        steps: "Review",
        rationale: "model path"
    ),
    Recommendation(
        title: "npm",
        affectedPath: "/Users/warrn/.npm/_cacache",
        estimatedBytes: 50,
        risk: .safeClean,
        command: "npm cache clean --force",
        steps: "Clean",
        rationale: "cache path"
    ),
]
let related = RecommendationEngine.relevantRecommendations(recommendations, selectedPath: "/Users/warrn/ComfyUI")
expect(related.count == 1 && related[0].title == "ComfyUI", "recommendations filter to selected treemap path")

let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("DiskLensChecks-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("A"), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("B"), withIntermediateDirectories: true)
try Data(repeating: 1, count: 4096).write(to: tempRoot.appendingPathComponent("A/file.bin"))
try Data(repeating: 2, count: 2048).write(to: tempRoot.appendingPathComponent("B/file.bin"))
let level = await DiskScanner().scanDirectoryLevel(url: tempRoot, maxChildrenPerNode: 1)
expect(level.item.children.contains { $0.name == "A" }, "directory level scan loads immediate children")
expect(level.item.children.count == 1, "directory level scan respects max child cap")
expect(level.scannedDirectories >= 3, "directory level scan reports measured directory entries")

let progressSink = ProgressSink()
let cappedScan = await DiskScanner().scan(
    options: ScanOptions(mode: .custom, customRoots: [tempRoot], maxChildrenPerNode: 1)
) { progress in
    progressSink.append(progress)
}
expect(cappedScan.items.first?.children.count == 1, "scan options apply max child cap to root scans")
expect(progressSink.last?.scannedDirectories ?? 0 >= 3, "scan progress reports measured directory entries")
expect(progressSink.containsPhase(.estimating), "scan progress reports estimating phase")
expect(progressSink.last?.phase == .finalizing, "scan progress reports finalizing phase before completion")
try? FileManager.default.removeItem(at: tempRoot)

let result = ScanResult(
    summary: ScanSummary(
        totalBytes: 100,
        usedBytes: 70,
        availableBytes: 30,
        dataVolumeBytes: 60,
        systemVolumeBytes: 10,
        scannedBytes: 40,
        scannedAt: Date(timeIntervalSince1970: 0),
        mode: .defaultScope,
        roots: ["/Users/warrn"],
        inaccessibleCount: 1,
        inaccessiblePaths: ["/Users/warrn/Library/Mail"],
        scanDurationSeconds: 5
    ),
    items: [
        ScanItem(
            path: "/Users/warrn/.cache/uv",
            name: "uv",
            sizeBytes: 40,
            depth: 0,
            parentPath: nil,
            kind: .directory,
            category: .cache,
            risk: .safeClean,
            reclaimableBytes: 36,
            recommendedAction: "uv cache clean",
            command: "uv cache clean",
            detail: "cache",
            isReadable: true,
            children: []
        )
    ],
    recommendations: []
)

let json = String(data: try ReportExporter.jsonData(for: result), encoding: .utf8) ?? ""
expect(json.contains("\"mode\" : \"defaultScope\""), "JSON export contains scan mode")
expect(json.contains("\"schemaVersion\" : 1"), "JSON export contains schema version")

let markdown = ReportExporter.markdown(for: result)
expect(markdown.contains("DiskLens 磁盘扫描报告"), "Markdown export contains title")
expect(markdown.contains("/Users/warrn/.cache/uv"), "Markdown export contains item path")
expect(markdown.contains("扫描耗时"), "Markdown export contains scan duration")
expect(markdown.contains("不可读路径摘要"), "Markdown export contains inaccessible path summary")

let duplicateRoot = FileManager.default.temporaryDirectory.appendingPathComponent("DiskLensDuplicateChecks-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: duplicateRoot, withIntermediateDirectories: true)
let duplicateData = Data(repeating: 7, count: 1_100_000)
let firstDuplicate = duplicateRoot.appendingPathComponent("model-a.bin")
let renamedDuplicate = duplicateRoot.appendingPathComponent("renamed-model.bin")
let sameSampleDifferentContent = duplicateRoot.appendingPathComponent("same-sample-different-content.bin")
try duplicateData.write(to: firstDuplicate)
try duplicateData.write(to: renamedDuplicate)
var nearDuplicateData = Data(repeating: 7, count: 1_000_000)
nearDuplicateData.append(Data(repeating: 8, count: 100_000))
try nearDuplicateData.write(to: sameSampleDifferentContent)
let duplicateItems = [
    ScanItem(
        path: firstDuplicate.path,
        name: firstDuplicate.lastPathComponent,
        sizeBytes: Int64(duplicateData.count),
        depth: 0,
        parentPath: nil,
        kind: .file,
        category: .aiModel,
        risk: .review,
        reclaimableBytes: 0,
        recommendedAction: "review",
        detail: "",
        isReadable: true,
        children: []
    ),
    ScanItem(
        path: renamedDuplicate.path,
        name: renamedDuplicate.lastPathComponent,
        sizeBytes: Int64(duplicateData.count),
        depth: 0,
        parentPath: nil,
        kind: .file,
        category: .aiModel,
        risk: .review,
        reclaimableBytes: 0,
        recommendedAction: "review",
        detail: "",
        isReadable: true,
        children: []
    ),
    ScanItem(
        path: sameSampleDifferentContent.path,
        name: sameSampleDifferentContent.lastPathComponent,
        sizeBytes: Int64(duplicateData.count),
        depth: 0,
        parentPath: nil,
        kind: .file,
        category: .aiModel,
        risk: .review,
        reclaimableBytes: 0,
        recommendedAction: "review",
        detail: "",
        isReadable: true,
        children: []
    ),
]
let duplicateResult = await DuplicateDetector.detect(in: duplicateItems)
expect(duplicateResult.groups.count == 1, "duplicate detector matches same-content files with different names")
expect(duplicateResult.totalDuplicateFiles == 2, "duplicate detector counts duplicate files")
expect(duplicateResult.groups.first?.files.contains { $0.name == sameSampleDifferentContent.lastPathComponent } == false, "duplicate detector uses full hash after quick hash")
try? FileManager.default.removeItem(at: duplicateRoot)

func writeAppBundle(root: URL, name: String, bundleID: String) throws {
    let appRoot = root.appendingPathComponent("\(name).app/Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)
    let plist: [String: String] = [
        "CFBundleIdentifier": bundleID,
        "CFBundleName": name,
        "CFBundleExecutable": name,
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: appRoot.appendingPathComponent("Info.plist"))
}

let appLeftoverRoot = FileManager.default.temporaryDirectory.appendingPathComponent("DiskLensLeftoverChecks-\(UUID().uuidString)")
let installedRoot = appLeftoverRoot.appendingPathComponent("Applications", isDirectory: true)
let libraryRoot = appLeftoverRoot.appendingPathComponent("Library", isDirectory: true)
try FileManager.default.createDirectory(at: installedRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent("Preferences", isDirectory: true), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent("Caches/com.example.Gone", isDirectory: true), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent("Application Support/Gone", isDirectory: true), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent("Containers/com.example.Installed", isDirectory: true), withIntermediateDirectories: true)
try Data(repeating: 1, count: 128).write(to: libraryRoot.appendingPathComponent("Preferences/com.example.Gone.plist"))
try Data(repeating: 2, count: 128).write(to: libraryRoot.appendingPathComponent("Preferences/com.example.Installed.plist"))
try Data(repeating: 3, count: 1024).write(to: libraryRoot.appendingPathComponent("Caches/com.example.Gone/blob"))
try Data(repeating: 4, count: 1024).write(to: libraryRoot.appendingPathComponent("Application Support/Gone/data"))
try writeAppBundle(root: installedRoot, name: "Installed", bundleID: "com.example.Installed")

let leftovers = await AppLeftoverScanner.scan(installedAppRoots: [installedRoot], libraryRoots: [libraryRoot])
expect(leftovers.items.contains { $0.bundleIdentifier == "com.example.Gone" && $0.kind == .preference }, "app leftover scanner finds orphan preferences")
expect(leftovers.items.contains { $0.bundleIdentifier == "com.example.Gone" && $0.kind == .cache }, "app leftover scanner finds orphan caches")
expect(leftovers.items.contains { $0.bundleIdentifier == "com.example.Gone" && $0.kind == .appSupport }, "app leftover scanner links app support by orphan app name")
expect(leftovers.items.contains { $0.bundleIdentifier == "com.example.Installed" } == false, "app leftover scanner ignores installed app leftovers")
expect(leftovers.defaultSelectedBytes > 0, "app leftover scanner estimates default selected bytes")
let cleanupResult = await AppLeftoverCleaner.cleanDefaultSelected(leftovers)
expect(cleanupResult.failedItems.isEmpty, "app leftover cleaner moves safe leftovers without failures")
expect(cleanupResult.cleanedItems.allSatisfy(\.isDefaultSelected), "app leftover cleaner only cleans default selected items")
expect(FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("Preferences/com.example.Gone.plist").path) == false, "app leftover cleaner trashes orphan preference")
expect(FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("Application Support/Gone").path), "app leftover cleaner leaves review app support in place")
try? FileManager.default.removeItem(at: appLeftoverRoot)

if failures.isEmpty {
    print("All DiskLens checks passed.")
} else {
    print("\(failures.count) DiskLens checks failed.")
    exit(1)
}
