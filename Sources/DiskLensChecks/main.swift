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
expect(npm.recommendedAction.contains("npm cache clean"), "npm cache exposes safe command")

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
try Data(repeating: 1, count: 4096).write(to: tempRoot.appendingPathComponent("A/file.bin"))
let level = await DiskScanner().scanDirectoryLevel(url: tempRoot)
expect(level.item.children.contains { $0.name == "A" }, "directory level scan loads immediate children")
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

if failures.isEmpty {
    print("All DiskLens checks passed.")
} else {
    print("\(failures.count) DiskLens checks failed.")
    exit(1)
}
