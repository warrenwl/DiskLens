import DiskLensCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let result = model.result {
                dashboard(result)
            } else {
                emptyState
            }
            Divider()
            statusBar
        }
        .task {
            model.loadCachedResult()
            if model.result == nil && !model.isScanning {
                model.startScan()
            }
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("扫描", selection: $model.selectedMode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 390)
                .disabled(model.isScanning)

                Button {
                    model.chooseCustomRoots()
                } label: {
                    Label("选择目录", systemImage: "folder.badge.gearshape")
                }
                .disabled(model.isScanning)

                Button {
                    model.isScanning ? model.cancelScan() : model.startScan()
                } label: {
                    Label(model.isScanning ? "停止" : "开始扫描", systemImage: model.isScanning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Menu {
                    Button("Markdown 报告") { model.exportMarkdown() }
                    Button("JSON 扫描结果") { model.exportJSON() }
                    Button("SVG 全景图") { model.exportSVG() }
                    Button("PNG 全景图") { model.exportPNG() }
                } label: {
                    Label("导出", systemImage: "square.and.arrow.down")
                }
                .disabled(model.result == nil)

                Button {
                    model.toggleDuplicates()
                } label: {
                    Label("重复文件", systemImage: "doc.on.doc.fill")
                }
                .disabled(model.result == nil)

                Button {
                    model.showHistory.toggle()
                } label: {
                    Label("历史", systemImage: "chart.xyaxis.line")
                }
                .disabled(model.scanHistory.isEmpty)
                .sheet(isPresented: $model.showHistory) {
                    ScanHistoryView(history: model.scanHistory)
                }
            }

            HStack(spacing: 10) {
                TextField("搜索路径、分类、建议", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240, idealWidth: 320)

                Picker("筛选", selection: $model.riskFilter) {
                    ForEach(RiskFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                Picker("大小", selection: $model.sizeThreshold) {
                    ForEach(SizeThreshold.allCases) { threshold in
                        Text(threshold.label).tag(threshold)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Picker("排序", selection: $model.sortOption) {
                    ForEach(ItemSortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func dashboard(_ result: ScanResult) -> some View {
        VStack(spacing: 0) {
            SummaryStrip(
                summary: result.summary,
                progress: model.progress,
                openSettings: model.openFullDiskAccessSettings
            )
            Divider()
            HSplitView {
                TreemapPanel(
                    items: model.visibleTreemapItems,
                    title: model.treemapTitle,
                    breadcrumbs: model.breadcrumbItems,
                    selectedItem: model.selectedItem,
                    selectedPath: model.selectedPath,
                    treemapRootPath: model.treemapRootPath,
                    loadingPath: model.loadingPath,
                    onSelect: model.selectTreemapItem,
                    onEnter: model.enterTreemapItem,
                    onBreadcrumb: model.jumpToBreadcrumb
                )
                    .frame(minWidth: 620)
                sidePanel()
                    .frame(minWidth: 390, idealWidth: 460)
            }
            Divider()
            if model.showDuplicates, let dupResult = model.duplicateResult {
                DuplicatePanel(result: dupResult)
                Divider()
            } else if model.isDetectingDuplicates {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在检测重复文件…")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                Divider()
            }
            ItemsTable(
                items: model.filteredItems,
                copyPath: model.copyPath,
                revealInFinder: model.revealInFinder,
                copyCommand: model.copy
            )
                .frame(minHeight: 220)
        }
    }

    private func sidePanel() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("清理建议")
                    .font(.title3.weight(.semibold))
                Spacer()
                if model.selectedPath != nil {
                    Button {
                        model.clearSelection()
                    } label: {
                        Label("取消选中", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            if let selected = model.selectedItem {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selected.name)
                        .font(.headline)
                    Text(selected.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(selected.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        RiskBadge(risk: selected.risk)
                        Text(ByteFormat.string(selected.sizeBytes))
                            .font(.callout.monospacedDigit())
                        Spacer()
                        if selected.kind == .directory && selected.path != model.treemapRootPath {
                            Button {
                                model.enterSelectedItem()
                            } label: {
                                Label(model.loadingPath == selected.path ? "加载中" : "进入目录", systemImage: model.loadingPath == selected.path ? "hourglass" : "arrow.down.right.circle")
                            }
                            .disabled(model.loadingPath == selected.path)
                        }
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.visibleRecommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("当前选中范围没有专门建议")
                                .font(.headline)
                            Text("可以返回上层，或查看底部表格里的路径级建议。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    ForEach(model.visibleRecommendations) { recommendation in
                        RecommendationRow(recommendation: recommendation) { command in
                            model.copy(command)
                        }
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .opacity(model.isScanning ? 1 : 0)
            Text(model.isScanning ? "正在建立磁盘画像…" : "点击开始扫描")
                .font(.title3.weight(.semibold))
            if !model.isScanning, let age = model.lastScanAge, model.cachedResult != nil {
                Button("加载上次扫描结果（\(age)）") {
                    model.restoreCachedResult()
                }
                .buttonStyle(.bordered)
            }
            Text("只读取磁盘占用并生成建议，不删除、不移动、不执行清理命令。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack {
            if model.isScanning {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Text(model.status)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let url = model.lastExportURL {
                Text(url.path)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .font(.footnote)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

private struct SummaryStrip: View {
    let summary: ScanSummary
    let progress: ScanProgress?
    let openSettings: () -> Void
    @State private var showInaccessible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                MetricView(title: "总容量", value: ByteFormat.string(summary.totalBytes), systemImage: "internaldrive")
                MetricView(title: "已用", value: ByteFormat.string(summary.usedBytes), systemImage: "chart.pie")
                MetricView(title: "可用", value: ByteFormat.string(summary.availableBytes), systemImage: "checkmark.circle")
                MetricView(title: "Data 卷", value: ByteFormat.string(summary.dataVolumeBytes), systemImage: "externaldrive")
                MetricView(title: progress == nil ? "本次扫描" : "已扫描", value: ByteFormat.string(progress?.scannedBytes ?? summary.scannedBytes), systemImage: "scope")
                Spacer()
                if summary.inaccessibleCount > 0 || !(progress?.inaccessiblePaths.isEmpty ?? true) {
                    Button {
                        openSettings()
                    } label: {
                        Label("完全磁盘访问", systemImage: "lock.open")
                    }
                    .help("打开系统设置，给 DiskLens 或终端授予完全磁盘访问权限")
                }
            }

            if let progress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 14) {
                        Text("当前：\(progress.currentPath.isEmpty ? "准备中" : progress.currentPath)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(progress.scannedDirectories) 目录")
                        Text("\(progress.scannedFiles) 文件")
                        Text("耗时 \(formatDuration(progress.elapsedSeconds))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }

            let inaccessiblePaths = progress?.inaccessiblePaths ?? summary.inaccessiblePaths
            if !inaccessiblePaths.isEmpty {
                DisclosureGroup(isExpanded: $showInaccessible) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(inaccessiblePaths.prefix(20), id: \.self) { path in
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if inaccessiblePaths.count > 20 {
                            Text("还有 \(inaccessiblePaths.count - 20) 项未显示")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("无法读取 \(inaccessiblePaths.count) 项，可能需要完全磁盘访问权限")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
    }
}

private struct MetricView: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
            }
        }
    }
}

private struct ItemsTable: View {
    let items: [ScanItem]
    let copyPath: (String) -> Void
    let revealInFinder: (String) -> Void
    let copyCommand: (String) -> Void

    var body: some View {
        Table(items) {
            TableColumn("大小") { item in
                Text(ByteFormat.string(item.sizeBytes))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110, max: 140)

            TableColumn("风险") { item in
                RiskBadge(risk: item.risk)
            }
            .width(min: 92, ideal: 110, max: 130)

            TableColumn("分类") { item in
                Text(item.category.label)
            }
            .width(min: 100, ideal: 120, max: 150)

            TableColumn("路径") { item in
                Text(item.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.path)
                    .contextMenu {
                        itemMenu(item)
                    }
            }

            TableColumn("建议") { item in
                Text(item.recommendedAction)
                    .lineLimit(1)
            }
            .width(min: 220, ideal: 320)

            TableColumn("操作") { item in
                Menu {
                    itemMenu(item)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .width(min: 48, ideal: 56, max: 70)
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: ScanItem) -> some View {
        Button("复制路径") {
            copyPath(item.path)
        }
        Button("Finder 中显示") {
            revealInFinder(item.path)
        }
        if let command = command(from: item.recommendedAction) {
            Divider()
            Button("复制建议命令") {
                copyCommand(command)
            }
        }
    }

    private func command(from action: String) -> String? {
        let marker = "可复制命令："
        guard let range = action.range(of: marker) else { return nil }
        let command = action[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }
}

private struct RecommendationRow: View {
    let recommendation: Recommendation
    let copyCommand: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(recommendation.title)
                    .font(.headline)
                Spacer()
                Text(ByteFormat.string(recommendation.estimatedBytes))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(recommendation.affectedPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(recommendation.affectedPath)
            Text(recommendation.steps)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if !recommendation.rationale.isEmpty {
                Text("依据：\(recommendation.rationale)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                RiskBadge(risk: recommendation.risk)
                Spacer()
                if let command = recommendation.command {
                    Button {
                        copyCommand(command)
                    } label: {
                        Label("复制命令", systemImage: "doc.on.doc")
                    }
                    .help(command)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RiskBadge: View {
    let risk: RiskLevel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(risk.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color.foreground)
            .background(color.background, in: Capsule())
    }

    private var color: (background: Color, foreground: Color) {
        let isDark = colorScheme == .dark
        switch risk {
        case .safeClean:
            return (Color.green.opacity(isDark ? 0.25 : 0.18), Color.green)
        case .review:
            return (Color.orange.opacity(isDark ? 0.28 : 0.20), Color.orange)
        case .keep:
            return (Color.gray.opacity(isDark ? 0.25 : 0.18), Color.secondary)
        case .system:
            return (Color.blue.opacity(isDark ? 0.22 : 0.16), Color.blue)
        }
    }
}
