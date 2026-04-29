import AppKit
import DiskLensCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum AppScreen {
    case home
    case panorama
    case cleanup
}

enum CleanupSectionKind: String, CaseIterable, Identifiable {
    case safe
    case leftovers
    case duplicates
    case largeFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safe: return "安全清理"
        case .leftovers: return "卸载残留"
        case .duplicates: return "重复文件"
        case .largeFiles: return "大文件"
        }
    }

    var subtitle: String {
        switch self {
        case .safe: return "默认选择，可移入废纸篓"
        case .leftovers: return "默认选择，只处理安全残留"
        case .duplicates: return "默认不选，保留每组第一个文件"
        case .largeFiles: return "默认不选，需确认用途"
        }
    }

    var systemImage: String {
        switch self {
        case .safe: return "checkmark.shield"
        case .leftovers: return "app.badge.checkmark"
        case .duplicates: return "doc.on.doc"
        case .largeFiles: return "tray.full"
        }
    }

    var defaultSelected: Bool {
        self == .safe || self == .leftovers
    }
}

struct CleanupCandidate: Identifiable, Equatable {
    var id: String { path }
    var title: String
    var path: String
    var sizeBytes: Int64
    var detail: String
    var risk: RiskLevel
    var isSelected: Bool
}

struct CleanupSection: Identifiable, Equatable {
    var id: CleanupSectionKind { kind }
    var kind: CleanupSectionKind
    var candidates: [CleanupCandidate]

    var selectedBytes: Int64 {
        candidates.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    var totalBytes: Int64 {
        candidates.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedCount: Int {
        candidates.filter(\.isSelected).count
    }

    var allSelected: Bool {
        !candidates.isEmpty && candidates.allSatisfy(\.isSelected)
    }
}

struct CleanupExecutionResult {
    var cleaned: [CleanupCandidate]
    var failures: [(candidate: CleanupCandidate, message: String)]

    var cleanedBytes: Int64 {
        cleaned.reduce(0) { $0 + $1.sizeBytes }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var currentScreen: AppScreen = .home
    @Published var result: ScanResult? {
        didSet {
            scanIndex = ScanTreeIndex(roots: result?.items ?? [])
        }
    }
    @Published var selectedMode: ScanMode = .defaultScope
    @Published var riskFilter: RiskFilter = .all
    @Published var isScanning = false
    @Published var status = "准备扫描"
    @Published var customRoots: [URL] = []
    @Published var lastExportURL: URL?
    @Published var progress: ScanProgress?
    @Published var treemapRootPath: String?
    @Published var selectedPath: String?
    @Published var searchText = "" {
        didSet {
            scheduleSearchUpdate()
        }
    }
    @Published var sizeThreshold: SizeThreshold = .over100MB
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
    @Published var appLeftoverResult: AppLeftoverResult?
    @Published var appLeftoverCleanupResult: AppLeftoverCleanupResult?
    @Published var isScanningAppLeftovers = false
    @Published var isCleaningAppLeftovers = false
    @Published var showAppLeftovers = false
    @Published var showCleanPlan = true
    @Published var showAppLeftoverCleanupConfirmation = false
    @Published var cleanupSections: [CleanupSection] = []
    @Published var isPreparingCleanup = false
    @Published var isExecutingCleanup = false
    @Published var showCleanupConfirmation = false
    @Published var cleanupExecutionResult: CleanupExecutionResult?
    @Published private var effectiveSearchText = ""

    private let scanner = DiskScanner()
    private var scanTask: Task<Void, Never>?
    private var duplicateTask: Task<Void, Never>?
    private var loadChildrenTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    private var appLeftoverTask: Task<Void, Never>?
    private var appLeftoverCleanupTask: Task<Void, Never>?
    private var cleanupPreparationTask: Task<Void, Never>?
    private var cleanupExecutionTask: Task<Void, Never>?
    private var scanIndex = ScanTreeIndex(roots: [])
    private var loadedPaths: Set<String> = []

    var selectedCleanupCandidates: [CleanupCandidate] {
        cleanupSections.flatMap { $0.candidates.filter(\.isSelected) }
    }

    var selectedCleanupBytes: Int64 {
        selectedCleanupCandidates.reduce(0) { $0 + $1.sizeBytes }
    }

    var canRunCleanup: Bool {
        !selectedCleanupCandidates.isEmpty && !isPreparingCleanup && !isExecutingCleanup
    }

    func loadCachedResult() {
        do {
            guard let cached = try ScanCacheManager.load() else {
                scanHistory = try ScanCacheManager.loadHistory()
                return
            }
            cachedResult = cached
            let interval = Date().timeIntervalSince(cached.summary.scannedAt)
            lastScanAge = formatRelativeTime(interval)
            scanHistory = try ScanCacheManager.loadHistory()
        } catch {
            status = "缓存读取失败：\(error.localizedDescription)"
        }
    }

    func restoreCachedResult() {
        guard let cached = cachedResult else { return }
        result = cached
        loadedPaths = Set(cached.items.map(\.path))
        status = "已恢复上次扫描结果"
    }

    func openHome() {
        currentScreen = .home
    }

    func openPanorama() {
        currentScreen = .panorama
        if result == nil && !isScanning {
            startScan()
        }
    }

    func openCleanup() {
        currentScreen = .cleanup
        prepareCleanupPlan()
    }

    func startDuplicateDetection() {
        guard let result, duplicateResult == nil else { return }
        isDetectingDuplicates = true
        showDuplicates = true
        duplicateTask = Task {
            let dupResult = await DuplicateDetector.detect(in: result.items) { progress in
                Task { @MainActor in
                    self.status = "重复检测：\(progress.phase.rawValue) \(progress.completedFiles)/\(progress.totalFiles)"
                }
            }
            guard !Task.isCancelled else {
                isDetectingDuplicates = false
                duplicateTask = nil
                status = "重复检测已取消"
                return
            }
            duplicateResult = dupResult
            isDetectingDuplicates = false
            duplicateTask = nil
            status = "重复检测完成：\(dupResult.totalDuplicateFiles) 个重复，浪费 \(ByteFormat.string(dupResult.totalWastedBytes))"
        }
    }

    func toggleDuplicates() {
        if isDetectingDuplicates {
            cancelDuplicateDetection()
            return
        }
        if duplicateResult == nil && !isDetectingDuplicates {
            startDuplicateDetection()
            return
        }
        showDuplicates.toggle()
    }

    func rescanDuplicates() {
        duplicateResult = nil
        startDuplicateDetection()
    }

    func toggleAppLeftovers() {
        if isCleaningAppLeftovers {
            cancelAppLeftoverCleanup()
            return
        }
        if isScanningAppLeftovers {
            cancelAppLeftoverScan()
            return
        }
        if appLeftoverResult == nil {
            startAppLeftoverScan()
            return
        }
        showAppLeftovers.toggle()
    }

    func rescanAppLeftovers() {
        appLeftoverResult = nil
        appLeftoverCleanupResult = nil
        startAppLeftoverScan()
    }

    func startAppLeftoverScan() {
        isScanningAppLeftovers = true
        showAppLeftovers = true
        appLeftoverCleanupResult = nil
        status = "正在扫描卸载残留…"
        appLeftoverTask = Task {
            let scan = await AppLeftoverScanner.scan()
            guard !Task.isCancelled else {
                isScanningAppLeftovers = false
                appLeftoverTask = nil
                status = "卸载残留扫描已取消"
                return
            }
            appLeftoverResult = scan
            isScanningAppLeftovers = false
            appLeftoverTask = nil
            status = "卸载残留扫描完成：\(scan.items.count) 项，默认可清理 \(ByteFormat.string(scan.defaultSelectedBytes))"
        }
    }

    var defaultAppLeftoverCleanupItems: [AppLeftoverItem] {
        appLeftoverResult?.items.filter(\.isDefaultSelected) ?? []
    }

    var defaultAppLeftoverCleanupBytes: Int64 {
        defaultAppLeftoverCleanupItems.reduce(0) { $0 + $1.sizeBytes }
    }

    func requestAppLeftoverCleanup() {
        guard !defaultAppLeftoverCleanupItems.isEmpty else {
            status = "没有默认可清理的卸载残留"
            return
        }
        showAppLeftoverCleanupConfirmation = true
    }

    func cleanDefaultAppLeftovers() {
        guard let result = appLeftoverResult else { return }
        showAppLeftoverCleanupConfirmation = false
        isCleaningAppLeftovers = true
        status = "正在将卸载残留移入废纸篓…"
        appLeftoverCleanupTask = Task {
            let cleanup = await AppLeftoverCleaner.cleanDefaultSelected(result)
            guard !Task.isCancelled else {
                isCleaningAppLeftovers = false
                appLeftoverCleanupTask = nil
                status = "卸载残留清理已取消"
                return
            }
            appLeftoverCleanupResult = cleanup
            if var current = appLeftoverResult {
                let cleanedPaths = Set(cleanup.cleanedItems.map(\.path))
                current.items.removeAll { cleanedPaths.contains($0.path) }
                appLeftoverResult = current
            }
            isCleaningAppLeftovers = false
            appLeftoverCleanupTask = nil
            status = "卸载残留已移入废纸篓：\(ByteFormat.string(cleanup.cleanedBytes))，失败 \(cleanup.failedItems.count) 项"
        }
    }

    func cancelAppLeftoverCleanup(updateStatus: Bool = true) {
        appLeftoverCleanupTask?.cancel()
        appLeftoverCleanupTask = nil
        isCleaningAppLeftovers = false
        if updateStatus {
            status = "正在取消卸载残留清理…"
        }
    }

    func cancelAppLeftoverScan(updateStatus: Bool = true) {
        appLeftoverTask?.cancel()
        appLeftoverTask = nil
        isScanningAppLeftovers = false
        if updateStatus {
            status = "正在取消卸载残留扫描…"
        }
    }

    func cancelDuplicateDetection(updateStatus: Bool = true) {
        duplicateTask?.cancel()
        duplicateTask = nil
        isDetectingDuplicates = false
        if updateStatus {
            status = "正在取消重复检测…"
        }
    }

    func prepareCleanupPlan() {
        cleanupPreparationTask?.cancel()
        cleanupExecutionResult = nil
        isPreparingCleanup = true
        status = "正在检索可清理内容…"
        cleanupPreparationTask = Task {
            let scanResult: ScanResult
            if let existing = result {
                scanResult = existing
            } else {
                isScanning = true
                let options = ScanOptions(mode: selectedMode, customRoots: customRoots)
                scanResult = await scanner.scan(options: options) { [weak self] progress in
                    Task { @MainActor in
                        self?.progress = progress
                        self?.status = "\(progress.phase.label)：\(progress.displayCurrentPath)"
                    }
                }
                guard !Task.isCancelled else {
                    isPreparingCleanup = false
                    isScanning = false
                    status = "一键清理检索已取消"
                    return
                }
                applyScanResult(scanResult, resetCleanup: false)
            }

            async let duplicateScan = DuplicateDetector.detect(in: scanResult.items)
            async let leftoverScan = AppLeftoverScanner.scan()
            let (duplicates, leftovers) = await (duplicateScan, leftoverScan)

            guard !Task.isCancelled else {
                isPreparingCleanup = false
                status = "一键清理检索已取消"
                return
            }

            duplicateResult = duplicates
            appLeftoverResult = leftovers
            cleanupSections = makeCleanupSections(duplicates: duplicates, leftovers: leftovers)
            isPreparingCleanup = false
            cleanupPreparationTask = nil
            status = "一键清理检索完成：已默认选择 \(ByteFormat.string(selectedCleanupBytes))"
        }
    }

    func toggleCleanupCandidate(sectionID: CleanupSectionKind, candidateID: String) {
        guard let sectionIndex = cleanupSections.firstIndex(where: { $0.kind == sectionID }),
              let candidateIndex = cleanupSections[sectionIndex].candidates.firstIndex(where: { $0.id == candidateID }) else {
            return
        }
        cleanupSections[sectionIndex].candidates[candidateIndex].isSelected.toggle()
    }

    func setCleanupSectionSelection(sectionID: CleanupSectionKind, selected: Bool) {
        guard let sectionIndex = cleanupSections.firstIndex(where: { $0.kind == sectionID }) else { return }
        for index in cleanupSections[sectionIndex].candidates.indices {
            cleanupSections[sectionIndex].candidates[index].isSelected = selected
        }
    }

    func requestOneClickCleanup() {
        guard canRunCleanup else {
            status = "没有已选择的清理项"
            return
        }
        showCleanupConfirmation = true
    }

    func executeSelectedCleanup() {
        let selected = selectedCleanupCandidates
        guard !selected.isEmpty else { return }
        showCleanupConfirmation = false
        isExecutingCleanup = true
        status = "正在将已选项目移入废纸篓…"
        cleanupExecutionTask = Task {
            var cleaned: [CleanupCandidate] = []
            var failures: [(candidate: CleanupCandidate, message: String)] = []
            var seen = Set<String>()

            for candidate in selected where seen.insert(candidate.path).inserted {
                if Task.isCancelled { break }
                do {
                    _ = try FileManager.default.trashItem(at: URL(fileURLWithPath: candidate.path), resultingItemURL: nil)
                    cleaned.append(candidate)
                } catch {
                    failures.append((candidate, error.localizedDescription))
                }
            }

            guard !Task.isCancelled else {
                isExecutingCleanup = false
                cleanupExecutionTask = nil
                status = "一键清理已取消"
                return
            }

            cleanupExecutionResult = CleanupExecutionResult(cleaned: cleaned, failures: failures)
            removeCleanedCandidates(paths: Set(cleaned.map(\.path)))
            isExecutingCleanup = false
            cleanupExecutionTask = nil
            status = "一键清理完成：已移入废纸篓 \(ByteFormat.string(cleanupExecutionResult?.cleanedBytes ?? 0))，失败 \(failures.count) 项"
        }
    }

    private func removeCleanedCandidates(paths: Set<String>) {
        for sectionIndex in cleanupSections.indices {
            cleanupSections[sectionIndex].candidates.removeAll { paths.contains($0.path) }
        }
    }

    private func makeCleanupSections(
        duplicates: DuplicateResult,
        leftovers: AppLeftoverResult
    ) -> [CleanupSection] {
        [
            CleanupSection(kind: .safe, candidates: safeCleanupCandidates()),
            CleanupSection(kind: .leftovers, candidates: leftoverCleanupCandidates(leftovers)),
            CleanupSection(kind: .duplicates, candidates: duplicateCleanupCandidates(duplicates)),
            CleanupSection(kind: .largeFiles, candidates: largeFileCleanupCandidates()),
        ]
    }

    private func safeCleanupCandidates() -> [CleanupCandidate] {
        scanIndex.flatItems
            .filter { $0.risk == .safeClean && $0.kind != .inaccessible && $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(80)
            .map { item in
                CleanupCandidate(
                    title: item.name,
                    path: item.path,
                    sizeBytes: item.sizeBytes,
                    detail: item.recommendedAction,
                    risk: item.risk,
                    isSelected: CleanupSectionKind.safe.defaultSelected
                )
            }
    }

    private func leftoverCleanupCandidates(_ leftovers: AppLeftoverResult) -> [CleanupCandidate] {
        leftovers.items
            .filter(\.isDefaultSelected)
            .map { item in
                CleanupCandidate(
                    title: "\(item.appName) · \(item.kind.label)",
                    path: item.path,
                    sizeBytes: item.sizeBytes,
                    detail: item.suggestedAction,
                    risk: item.risk,
                    isSelected: CleanupSectionKind.leftovers.defaultSelected
                )
            }
    }

    private func duplicateCleanupCandidates(_ duplicates: DuplicateResult) -> [CleanupCandidate] {
        duplicates.groups.flatMap { group in
            group.files.dropFirst().map { file in
                CleanupCandidate(
                    title: file.name,
                    path: file.path,
                    sizeBytes: file.sizeBytes,
                    detail: "重复文件，默认保留每组第一个文件",
                    risk: file.risk,
                    isSelected: CleanupSectionKind.duplicates.defaultSelected
                )
            }
        }
    }

    private func largeFileCleanupCandidates() -> [CleanupCandidate] {
        scanIndex.flatItems
            .filter { $0.kind == .file && $0.sizeBytes >= SizeThreshold.over1GB.minimumBytes && $0.risk != .system }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(80)
            .map { item in
                CleanupCandidate(
                    title: item.name,
                    path: item.path,
                    sizeBytes: item.sizeBytes,
                    detail: "大文件，需确认用途后再清理",
                    risk: item.risk,
                    isSelected: CleanupSectionKind.largeFiles.defaultSelected
                )
            }
    }

    private func formatRelativeTime(_ interval: TimeInterval) -> String {
        if interval < 60 { return "\(Int(interval)) 秒前" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }

    private func scheduleSearchUpdate() {
        searchDebounceTask?.cancel()
        let pendingText = searchText
        if pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            effectiveSearchText = pendingText
            return
        }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.effectiveSearchText = pendingText
            }
        }
    }

    var filteredItems: [ScanItem] {
        guard result != nil else { return [] }
        return ScanItemFilter.filter(
            items: scanIndex.flatItems,
            riskFilter: riskFilter,
            selectedPath: selectedPath,
            query: effectiveSearchText,
            sizeThreshold: sizeThreshold,
            sort: sortOption
        )
    }

    var visibleTreemapItems: [ScanItem] {
        guard result != nil else { return [] }
        let scopedItems = scanIndex.treemapItems(rootPath: treemapRootPath)
        return ScanItemFilter.filter(
            items: scopedItems,
            riskFilter: riskFilter,
            selectedPath: nil,
            query: effectiveSearchText,
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
        guard result != nil else { return [("扫描结果", nil)] }
        return scanIndex.breadcrumbs(rootPath: treemapRootPath)
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
        loadChildrenTask?.cancel()
        loadChildrenTask = nil
        cleanupPreparationTask?.cancel()
        cleanupExecutionTask?.cancel()
        cancelDuplicateDetection(updateStatus: false)
        cancelAppLeftoverScan(updateStatus: false)
        cancelAppLeftoverCleanup(updateStatus: false)
        isScanning = true
        status = "正在扫描 \(selectedMode.label)…"
        progress = ScanProgress(
            phase: .preparing,
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
                    self?.status = "\(progress.phase.label)：\(progress.displayCurrentPath)"
                }
            }
            applyScanResult(scanResult, resetCleanup: true)
        }
    }

    private func applyScanResult(_ scanResult: ScanResult, resetCleanup: Bool) {
        result = scanResult
        loadedPaths = Set(scanResult.items.map(\.path))
        treemapRootPath = nil
        selectedPath = nil
        isScanning = false
        progress = nil
        duplicateResult = nil
        showDuplicates = false
        isDetectingDuplicates = false
        if resetCleanup {
            appLeftoverResult = nil
            appLeftoverCleanupResult = nil
            cleanupSections = []
            cleanupExecutionResult = nil
        }
        showAppLeftovers = false
        isScanningAppLeftovers = false
        isCleaningAppLeftovers = false

        if let cached = self.cachedResult {
            self.delta = ScanCacheManager.computeDelta(old: cached, new: scanResult)
        }
        var warnings: [String] = []
        do {
            try ScanCacheManager.save(scanResult)
        } catch {
            warnings.append("缓存保存失败：\(error.localizedDescription)")
        }
        self.cachedResult = scanResult
        self.lastScanAge = "刚刚"
        do {
            try ScanCacheManager.appendToHistory(scanResult.summary)
            self.scanHistory = try ScanCacheManager.loadHistory()
        } catch {
            warnings.append("历史保存失败：\(error.localizedDescription)")
        }

        if scanResult.summary.isCancelled {
            status = "扫描已取消：保留部分结果 \(ByteFormat.string(scanResult.summary.scannedBytes))\(warningSuffix(warnings))"
        } else {
            status = "扫描完成：\(ByteFormat.string(scanResult.summary.scannedBytes))，无法读取 \(scanResult.summary.inaccessibleCount) 项\(warningSuffix(warnings))"
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        loadChildrenTask?.cancel()
        loadChildrenTask = nil
        loadingPath = nil
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
        guard result != nil else { return nil }
        return scanIndex.find(path: path)
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
        loadChildrenTask?.cancel()
        loadingPath = item.path
        status = "\(ScanPhase.expanding.label)：\(item.path)"
        let parentPath = item.parentPath
        loadChildrenTask = Task {
            let level = await scanner.scanDirectoryLevel(url: URL(fileURLWithPath: item.path), parentPath: parentPath)
            guard !Task.isCancelled else {
                if loadingPath == item.path {
                    loadingPath = nil
                    status = "已取消加载：\(item.name)"
                }
                return
            }
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
            loadChildrenTask = nil
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

    private func warningSuffix(_ warnings: [String]) -> String {
        warnings.isEmpty ? "" : "；" + warnings.joined(separator: "；")
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
