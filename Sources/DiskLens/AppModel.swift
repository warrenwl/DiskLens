import AppKit
import DiskLensCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var result: ScanResult?
    @Published var selectedMode: ScanMode = .defaultScope
    @Published var riskFilter: RiskFilter = .all
    @Published var isScanning = false
    @Published var status = "准备扫描"
    @Published var customRoots: [URL] = []
    @Published var lastExportURL: URL?
    @Published var progress: ScanProgress?
    @Published var treemapRootPath: String?
    @Published var selectedPath: String?
    @Published var searchText = ""
    @Published var sizeThreshold: SizeThreshold = .all
    @Published var sortOption: ItemSortOption = .size
    @Published var loadingPath: String?
    @Published var cachedResult: ScanResult?
    @Published var delta: ScanDelta?
    @Published var lastScanAge: String?
    @Published var scanHistory: [ScanSummary] = []
    @Published var showHistory = false
    @Published var duplicateResult: DuplicateResult?
    @Published var isDetectingDuplicates = false
    @Published var showDuplicates = false

    private let scanner = DiskScanner()
    private var scanTask: Task<Void, Never>?
    private var duplicateTask: Task<Void, Never>?
    private var loadedPaths: Set<String> = []

    func loadCachedResult() {
        if let cached = try? ScanCacheManager.load() {
            cachedResult = cached
            let interval = Date().timeIntervalSince(cached.summary.scannedAt)
            lastScanAge = formatRelativeTime(interval)
        }
        scanHistory = (try? ScanCacheManager.loadHistory()) ?? []
    }

    func restoreCachedResult() {
        guard let cached = cachedResult else { return }
        result = cached
        loadedPaths = Set(cached.items.map(\.path))
        status = "已恢复上次扫描结果"
    }

    func startDuplicateDetection() {
        guard let result, duplicateResult == nil else { return }
        isDetectingDuplicates = true
        duplicateTask = Task {
            let dupResult = await DuplicateDetector.detect(in: result.items) { progress in
                Task { @MainActor in
                    self.status = "重复检测：\(progress.phase.rawValue) \(progress.completedFiles)/\(progress.totalFiles)"
                }
            }
            guard !Task.isCancelled else { return }
            duplicateResult = dupResult
            isDetectingDuplicates = false
            status = "重复检测完成：\(dupResult.totalDuplicateFiles) 个重复，浪费 \(ByteFormat.string(dupResult.totalWastedBytes))"
        }
    }

    func toggleDuplicates() {
        if duplicateResult == nil && !isDetectingDuplicates {
            startDuplicateDetection()
        }
        showDuplicates.toggle()
    }

    private func formatRelativeTime(_ interval: TimeInterval) -> String {
        if interval < 60 { return "\(Int(interval)) 秒前" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }

    var filteredItems: [ScanItem] {
        guard let result else { return [] }
        return ScanItemFilter.filter(
            items: result.items.flatMap { RecommendationEngine.flatten($0) },
            riskFilter: riskFilter,
            selectedPath: selectedPath,
            query: searchText,
            sizeThreshold: sizeThreshold,
            sort: sortOption
        )
    }

    var visibleTreemapItems: [ScanItem] {
        guard let result else { return [] }
        let scopedItems = ScanTree.treemapItems(roots: result.items, rootPath: treemapRootPath)
        return ScanItemFilter.filter(
            items: scopedItems,
            riskFilter: riskFilter,
            selectedPath: nil,
            query: searchText,
            sizeThreshold: sizeThreshold,
            sort: .size
        )
    }

    var treemapTitle: String {
        guard let treemapRootPath, let item = findItem(path: treemapRootPath) else {
            return "扫描结果"
        }
        return item.name
    }

    var breadcrumbItems: [(label: String, path: String?)] {
        guard let result else { return [("扫描结果", nil)] }
        return ScanTree.breadcrumbs(rootPath: treemapRootPath, roots: result.items)
    }

    var selectedItem: ScanItem? {
        guard let selectedPath else { return nil }
        return findItem(path: selectedPath)
    }

    var visibleRecommendations: [Recommendation] {
        guard let result else { return [] }
        return RecommendationEngine.relevantRecommendations(result.recommendations, selectedPath: selectedPath)
    }

    func startScan() {
        scanTask?.cancel()
        isScanning = true
        status = "正在扫描 \(selectedMode.label)…"
        progress = ScanProgress(
            currentPath: "",
            scannedDirectories: 0,
            scannedFiles: 0,
            scannedBytes: 0,
            inaccessiblePaths: [],
            startedAt: Date(),
            updatedAt: Date(),
            isCancelled: false
        )
        let options = ScanOptions(mode: selectedMode, customRoots: customRoots)

        scanTask = Task {
            let scanResult = await scanner.scan(options: options) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = progress
                    self?.status = "正在扫描：\(progress.displayCurrentPath)"
                }
            }
            result = scanResult
            loadedPaths = Set(scanResult.items.map(\.path))
            treemapRootPath = nil
            selectedPath = nil
            isScanning = false
            progress = nil
            duplicateResult = nil
            showDuplicates = false
            isDetectingDuplicates = false
            duplicateTask?.cancel()

            if let cached = self.cachedResult {
                self.delta = ScanCacheManager.computeDelta(old: cached, new: scanResult)
            }
            try? ScanCacheManager.save(scanResult)
            self.cachedResult = scanResult
            self.lastScanAge = "刚刚"
            try? ScanCacheManager.appendToHistory(scanResult.summary)
            self.scanHistory = (try? ScanCacheManager.loadHistory()) ?? []

            if scanResult.summary.isCancelled {
                status = "扫描已取消：保留部分结果 \(ByteFormat.string(scanResult.summary.scannedBytes))"
            } else {
                status = "扫描完成：\(ByteFormat.string(scanResult.summary.scannedBytes))，无法读取 \(scanResult.summary.inaccessibleCount) 项"
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
        progress = progress.map {
            var copy = $0
            copy.isCancelled = true
            copy.updatedAt = Date()
            return copy
        }
        status = "正在取消扫描…"
    }

    func chooseCustomRoots() {
        let panel = NSOpenPanel()
        panel.title = "选择要扫描的目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            customRoots = panel.urls
            selectedMode = .custom
            startScan()
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "已复制命令"
    }

    func copyPath(_ path: String) {
        copy(path)
        status = "已复制路径"
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        status = "已在 Finder 中定位"
    }

    func selectTreemapItem(_ item: ScanItem) {
        selectedPath = item.path
        if status.hasPrefix("当前已经是最后一层") {
            status = "已选中：\(item.name)"
        }
    }

    func enterTreemapItem(_ item: ScanItem) {
        selectedPath = item.path
        guard item.kind == .directory else { return }
        if item.path == treemapRootPath {
            status = "当前已经在该目录内"
            return
        }
        if !item.children.isEmpty {
            treemapRootPath = item.path
            status = "已进入：\(item.name)"
            return
        }
        if loadedPaths.contains(item.path) {
            status = "当前已经是最后一层：\(item.name)"
            return
        }
        loadChildrenAndEnter(item)
    }

    func jumpToBreadcrumb(path: String?) {
        treemapRootPath = path
        selectedPath = path
        if let path, let item = findItem(path: path) {
            status = "已返回：\(item.name)"
        } else {
            status = "已返回扫描结果"
        }
    }

    func clearSelection() {
        selectedPath = nil
        if status.hasPrefix("当前已经是最后一层") {
            status = "已取消选中"
        }
    }

    func enterSelectedItem() {
        guard let selectedItem else { return }
        enterTreemapItem(selectedItem)
    }

    func findItem(path: String) -> ScanItem? {
        guard let result else { return nil }
        return ScanTree.find(path: path, in: result.items)
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func exportMarkdown() {
        guard let result else { return }
        save(text: ReportExporter.markdown(for: result), defaultName: "DiskLens-Report.md", type: .plainText)
    }

    func exportJSON() {
        guard let result else { return }
        do {
            let data = try ReportExporter.jsonData(for: result)
            save(data: data, defaultName: "DiskLens-Scan.json", type: .json)
        } catch {
            status = "JSON 导出失败：\(error.localizedDescription)"
        }
    }

    func exportSVG() {
        guard let result else { return }
        save(text: ReportExporter.svg(for: result), defaultName: "DiskLens-Treemap.svg", type: UTType.svg)
    }

    func exportPNG() {
        guard let result else { return }
        guard let data = ReportExporter.pngData(for: result) else {
            status = "PNG 导出失败"
            return
        }
        save(data: data, defaultName: "DiskLens-Treemap.png", type: .png)
    }

    private func save(text: String, defaultName: String, type: UTType) {
        guard let data = text.data(using: .utf8) else { return }
        save(data: data, defaultName: defaultName, type: type)
    }

    private func save(data: Data, defaultName: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url, options: .atomic)
                lastExportURL = url
                status = "已导出：\(url.lastPathComponent)"
            } catch {
                status = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private func loadChildrenAndEnter(_ item: ScanItem) {
        guard loadingPath != item.path else { return }
        loadingPath = item.path
        status = "正在加载下一层：\(item.path)"
        let parentPath = item.parentPath
        Task {
            let level = await scanner.scanDirectoryLevel(url: URL(fileURLWithPath: item.path), parentPath: parentPath)
            guard var current = result else {
                loadingPath = nil
                return
            }
            current.items = current.items.map { replaceItem(path: item.path, replacement: level.item, in: $0) }
            current.recommendations = RecommendationEngine.recommendations(from: current.items)
            current.summary.inaccessiblePaths = Array((current.summary.inaccessiblePaths + level.inaccessiblePaths).prefix(200))
            current.summary.inaccessibleCount = current.summary.inaccessiblePaths.count
            result = current
            loadedPaths.insert(item.path)

            if level.item.children.isEmpty {
                status = "当前已经是最后一层：\(item.name)"
            } else {
                treemapRootPath = item.path
                status = "已加载：\(item.name)"
            }
            selectedPath = item.path
            loadingPath = nil
        }
    }

    private func replaceItem(path: String, replacement: ScanItem, in item: ScanItem) -> ScanItem {
        if item.path == path {
            return replacement
        }
        var copy = item
        copy.children = item.children.map { replaceItem(path: path, replacement: replacement, in: $0) }
        return copy
    }
}

extension UTType {
    static let svg = UTType(filenameExtension: "svg") ?? .xml
}

private extension ScanProgress {
    var displayCurrentPath: String {
        guard !currentPath.isEmpty else { return "准备中" }
        return currentPath
    }
}
