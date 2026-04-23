import AppKit
import DiskLensCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(spacing: 0) {
            switch model.currentScreen {
            case .home:
                homeScreen
            case .panorama:
                panoramaScreen
            case .cleanup:
                cleanupScreen
            }
            Divider()
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            model.loadCachedResult()
        }
        .confirmationDialog(
            "将默认安全的卸载残留移入废纸篓？",
            isPresented: $model.showAppLeftoverCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("移入废纸篓", role: .destructive) {
                model.cleanDefaultAppLeftovers()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将处理 \(model.defaultAppLeftoverCleanupItems.count) 项，约 \(ByteFormat.string(model.defaultAppLeftoverCleanupBytes))。仅处理可安全清理项，不会永久删除。")
        }
        .confirmationDialog(
            "将已选项目移入废纸篓？",
            isPresented: $model.showCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("移入废纸篓", role: .destructive) {
                model.executeSelectedCleanup()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将处理 \(model.selectedCleanupCandidates.count) 项，约 \(ByteFormat.string(model.selectedCleanupBytes))。DiskLens 只会移动到废纸篓，不会永久删除。")
        }
    }

    private var homeScreen: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 34, height: 34)
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                        Text("DiskLens")
                            .font(.title2.weight(.bold))
                    }
                    Spacer()
                    if let age = model.lastScanAge, model.cachedResult != nil {
                        Text("上次扫描 \(age)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 1160)
                .padding(.horizontal, 34)
                .padding(.top, 30)

                Spacer(minLength: 18)

                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .center, spacing: 0) {
                        Spacer(minLength: 20)
                        HomeSignalMark()
                            .padding(.bottom, 24)
                        HStack(spacing: 0) {
                            Text("看清磁盘")
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("谨慎")
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("清理")
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.green, .teal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .fixedSize()
                        Text("用 Treemap 定位空间大户，用复核式清理把安全项目统一移入废纸篓。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(5)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)
                            .frame(maxWidth: 460)
                        HStack(spacing: 10) {
                            HomeTrustPill(text: "只移入废纸篓", systemImage: "trash", tint: .green)
                            HomeTrustPill(text: "默认保护用户数据", systemImage: "lock.shield", tint: .blue)
                            HomeTrustPill(text: "可视化定位", systemImage: "square.grid.3x3", tint: .orange)
                        }
                        .padding(.top, 22)

                        Spacer(minLength: 20)

                        HomeDiskUsageBar(summary: model.result?.summary, cachedSummary: model.cachedResult?.summary)

                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.secondary.opacity(0.10), lineWidth: 0.5)
                    }

                    VStack(spacing: 14) {
                        Spacer(minLength: 20)
                        HomeStatusStrip(
                            title: model.cachedResult == nil ? "未加载历史扫描" : "已有历史扫描",
                            subtitle: model.lastScanAge.map { "上次扫描 \($0)" } ?? "进入磁盘全景开始第一次扫描"
                        )
                        HomeActionButton(
                            title: "磁盘全景",
                            subtitle: "用矩形面积看清每一块空间占用",
                            systemImage: "square.grid.3x3.fill",
                            tint: .blue,
                            action: model.openPanorama
                        )
                        HomeActionButton(
                            title: "一键清理",
                            subtitle: "扫描候选项，勾选后统一移入废纸篓",
                            systemImage: "trash",
                            tint: .green,
                            action: model.openCleanup
                        )

                        Spacer(minLength: 12)

                        HomeFeatureRow()

                        Spacer(minLength: 20)
                    }
                    .frame(width: 430)
                    .padding(.horizontal, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.secondary.opacity(0.10), lineWidth: 0.5)
                    }
                }
                .frame(maxWidth: 1160)
                .padding(.horizontal, 34)

                Spacer(minLength: 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panoramaScreen: some View {
        VStack(spacing: 0) {
            panoramaToolbar
            Divider()
            if let result = model.result {
                dashboard(result)
            } else {
                emptyState
            }
        }
    }

    private var panoramaToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.openHome()
                } label: {
                    Label("首页", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                Picker("扫描", selection: $model.selectedMode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
                .disabled(model.isScanning)

                Button {
                    model.chooseCustomRoots()
                } label: {
                    Label("选择目录", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)
                .disabled(model.isScanning)

                Button {
                    model.isScanning ? model.cancelScan() : model.startScan()
                } label: {
                    Label(model.isScanning ? "停止" : "开始扫描", systemImage: model.isScanning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isScanning ? .red : .blue)

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
                    model.showHistory.toggle()
                } label: {
                    Label("历史", systemImage: "chart.xyaxis.line")
                }
                .disabled(model.scanHistory.isEmpty)
                .sheet(isPresented: $model.showHistory) {
                    ScanHistoryView(history: model.scanHistory)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("搜索路径、分类、建议", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)

                Divider()
                    .frame(height: 18)

                Picker("筛选", selection: $model.riskFilter) {
                    ForEach(RiskFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Picker("大小", selection: $model.sizeThreshold) {
                    ForEach(SizeThreshold.allCases) { threshold in
                        Text(threshold.label).tag(threshold)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Picker("排序", selection: $model.sortOption) {
                    ForEach(ItemSortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                Spacer()

                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var cleanupScreen: some View {
        VStack(spacing: 0) {
            cleanupToolbar
            Divider()
            if model.isPreparingCleanup {
                cleanupPreparingView
            } else {
                cleanupSectionsView
            }
        }
    }

    private var cleanupToolbar: some View {
        HStack(spacing: 12) {
            Button {
                model.openHome()
            } label: {
                Label("首页", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 1) {
                Text("一键清理")
                    .font(.headline)
                Text("已选 \(model.selectedCleanupCandidates.count) 项，约 \(ByteFormat.string(model.selectedCleanupBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isPreparingCleanup || model.isExecutingCleanup {
                ProgressView()
                    .scaleEffect(0.7)
                Text(model.isPreparingCleanup ? "检索中…" : "清理中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.prepareCleanupPlan()
            } label: {
                Label("重新检索", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(model.isPreparingCleanup || model.isExecutingCleanup)

            Button {
                model.requestOneClickCleanup()
            } label: {
                Label(model.isExecutingCleanup ? "清理中" : "一键清理", systemImage: model.isExecutingCleanup ? "hourglass" : "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!model.canRunCleanup)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var cleanupPreparingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在检索可清理内容…")
                .font(.title3.weight(.semibold))
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cleanupSectionsView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let cleanupResult = model.cleanupExecutionResult {
                    CleanupResultBanner(result: cleanupResult)
                }
                ForEach(model.cleanupSections) { section in
                    CleanupSectionView(
                        section: section,
                        toggleSection: {
                            model.setCleanupSectionSelection(sectionID: section.kind, selected: !section.allSelected)
                        },
                        toggleCandidate: { candidate in
                            model.toggleCleanupCandidate(sectionID: section.kind, candidateID: candidate.id)
                        },
                        revealInFinder: model.revealInFinder,
                        copyPath: model.copyPath
                    )
                }
                if model.cleanupSections.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("暂无清理候选")
                            .font(.title3.weight(.semibold))
                        Button("重新检索") {
                            model.prepareCleanupPlan()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .padding(18)
        }
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
                panoramaInspector()
                    .frame(minWidth: 390, idealWidth: 460)
            }
            Divider()
            ItemsTable(
                items: model.filteredItems,
                copyPath: model.copyPath,
                revealInFinder: model.revealInFinder,
                copyCommand: model.copy
            )
                .frame(minHeight: 220)
        }
    }

    private func panoramaInspector() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("选中详情")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.selectedPath != nil {
                    Button {
                        model.clearSelection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let selected = model.selectedItem {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selected.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Text(selected.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Divider()

                    HStack(spacing: 6) {
                        RiskBadge(risk: selected.risk)
                        Text(ByteFormat.string(selected.sizeBytes))
                            .font(.callout.weight(.bold).monospacedDigit())
                        Spacer()
                        if selected.kind == .directory && selected.path != model.treemapRootPath {
                            Button {
                                model.enterSelectedItem()
                            } label: {
                                Label(model.loadingPath == selected.path ? "加载中" : "进入", systemImage: model.loadingPath == selected.path ? "hourglass" : "arrow.down.right.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(model.loadingPath == selected.path)
                        }
                    }

                    Text(selected.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        PanoramaInspectorStat(title: "分类", value: selected.category.label)
                        PanoramaInspectorStat(title: "类型", value: selected.kind.rawValue)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.secondary.opacity(0.10), lineWidth: 0.5)
                }
            }

            if model.selectedItem == nil {
                VStack(alignment: .center, spacing: 10) {
                    Spacer()
                    Image(systemName: "cursorarrow.click")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text("点击矩形查看详情")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("磁盘全景只用于空间观察和定位。\n清理操作请回到首页进入一键清理。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
            Spacer()
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
        HStack(spacing: 8) {
            if model.isScanning {
                ProgressView()
                    .scaleEffect(0.6)
            } else if model.isExecutingCleanup || model.isPreparingCleanup {
                ProgressView()
                    .scaleEffect(0.6)
            }
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let url = model.lastExportURL {
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.caption2)
                    Text(url.lastPathComponent)
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
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
                        Text("\(progress.phase.label)：\(progress.currentPath.isEmpty ? "准备中" : progress.currentPath)")
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
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.blue.opacity(0.08))
                    .frame(width: 28, height: 28)
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.callout.weight(.bold).monospacedDigit())
            }
        }
    }
}

private struct HomeActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [tint.opacity(isHovered ? 0.28 : 0.14), tint.opacity(0.04)],
                                center: .center,
                                startRadius: 4,
                                endRadius: 34
                            )
                        )
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint.opacity(isHovered ? 0.8 : 0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 108)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: isHovered ? tint.opacity(0.12) : .black.opacity(0.03), radius: isHovered ? 8 : 2, y: isHovered ? 3 : 1)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tint.opacity(isHovered ? 0.4 : 0.18), lineWidth: 1)
            }
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.18), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct HomeStatusStrip: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.secondary.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.02), radius: 2, y: 1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.secondary.opacity(0.10), lineWidth: 0.5)
        }
    }
}

private struct HomeSignalMark: View {
    @State private var pulse = false
    @State private var wavePhase: CGFloat = 0

    var body: some View {
        ZStack(alignment: .center) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.green.opacity(0.18), Color.green.opacity(0.04)],
                        center: .center,
                        startRadius: 30,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .scaleEffect(pulse ? 1.06 : 1.0)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.green.opacity(0.08), .green.opacity(0.35), .green.opacity(0.08)],
                        center: .center
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(Double(wavePhase)))

            Circle()
                .stroke(Color.green.opacity(0.12), lineWidth: 0.5)
                .frame(width: 110, height: 110)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 56))
                path.addLine(to: CGPoint(x: 40, y: 56))
                path.addLine(to: CGPoint(x: 58, y: 16))
                path.addLine(to: CGPoint(x: 82, y: 96))
                path.addLine(to: CGPoint(x: 104, y: 28))
                path.addLine(to: CGPoint(x: 125, y: 56))
                path.addLine(to: CGPoint(x: 175, y: 56))
            }
            .stroke(
                LinearGradient(
                    colors: [.green.opacity(0.5), .green, .green.opacity(0.5)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 175, height: 112)
            .shadow(color: .green.opacity(0.4), radius: 8)
        }
        .frame(width: 220, height: 220)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                wavePhase = 360
            }
        }
    }
}

private struct HomeDiskUsageBar: View {
    let summary: ScanSummary?
    let cachedSummary: ScanSummary?
    @Environment(\.colorScheme) private var colorScheme

    private var data: ScanSummary? { summary ?? cachedSummary }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("磁盘用量")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let data {
                    Text("\(ByteFormat.string(data.usedBytes)) / \(ByteFormat.string(data.totalBytes))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let data {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.secondary.opacity(colorScheme == .dark ? 0.18 : 0.10))
                        let ratio = data.totalBytes > 0 ? CGFloat(data.usedBytes) / CGFloat(data.totalBytes) : 0
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: ratio > 0.85 ? [.orange, .red] : [.green, .teal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * min(ratio, 1.0))
                    }
                }
                .frame(height: 8)

                HStack(spacing: 16) {
                    HomeDiskStat(label: "已用", value: ByteFormat.string(data.usedBytes), color: .green)
                    HomeDiskStat(label: "可用", value: ByteFormat.string(data.availableBytes), color: .blue)
                    HomeDiskStat(label: "Data 卷", value: ByteFormat.string(data.dataVolumeBytes), color: .secondary)
                }
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.secondary.opacity(0.06))
                    .frame(height: 8)
                    .overlay {
                        Text("扫描后显示用量")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .padding(14)
        .frame(maxWidth: 480)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.secondary.opacity(colorScheme == .dark ? 0.06 : 0.04))
        )
    }
}

private struct HomeDiskStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

private struct HomeFeatureRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("核心能力")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                HomeFeatureItem(icon: "chart.bar.doc.horizontal", title: "智能分类", desc: "AI模型、缓存、构建工具")
                HomeFeatureItem(icon: "doc.on.doc", title: "重复检测", desc: "SHA-256 精确比对")
                HomeFeatureItem(icon: "app.dashed", title: "残留扫描", desc: "自动发现卸载残留")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.secondary.opacity(0.04))
        )
    }
}

private struct HomeFeatureItem: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(desc)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeTrustPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 0.5)
        }
    }
}

private struct CleanupSectionView: View {
    let section: CleanupSection
    let toggleSection: () -> Void
    let toggleCandidate: (CleanupCandidate) -> Void
    let revealInFinder: (String) -> Void
    let copyPath: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: toggleSection) {
                    Image(systemName: section.allSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(section.kind.defaultSelected ? .green : .secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(sectionTint.opacity(colorScheme == .dark ? 0.20 : 0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: section.kind.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(sectionTint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.kind.title)
                        .font(.headline)
                    Text(section.kind.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("\(section.selectedCount)/\(section.candidates.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(ByteFormat.string(section.selectedBytes))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(section.selectedBytes > 0 ? sectionTint : .secondary)

                if !section.candidates.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "收起列表" : "展开列表")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                if !section.candidates.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }

            if isExpanded {
                if section.candidates.isEmpty {
                    Text("暂无候选项")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                } else {
                    Divider()
                        .padding(.horizontal, 14)
                    VStack(spacing: 0) {
                        ForEach(Array(section.candidates.prefix(24).enumerated()), id: \.element.id) { index, candidate in
                            CleanupCandidateRow(
                                candidate: candidate,
                                toggle: { toggleCandidate(candidate) },
                                revealInFinder: revealInFinder,
                                copyPath: copyPath
                            )
                            if index < min(section.candidates.count, 24) - 1 {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)

                    if section.candidates.count > 24 {
                        Text("还有 \(section.candidates.count - 24) 项未显示")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.02), radius: 2, y: 1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.secondary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var sectionTint: Color {
        switch section.kind {
        case .safe: return .green
        case .leftovers: return .blue
        case .duplicates: return .orange
        case .largeFiles: return .purple
        }
    }
}

private struct CleanupCandidateRow: View {
    let candidate: CleanupCandidate
    let toggle: () -> Void
    let revealInFinder: (String) -> Void
    let copyPath: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: candidate.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(candidate.isSelected ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(candidate.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormat.string(candidate.sizeBytes))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)

            RiskBadge(risk: candidate.risk)

            Button {
                copyPath(candidate.path)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("复制路径")

            Button {
                revealInFinder(candidate.path)
            } label: {
                Image(systemName: "finder")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Finder 中显示")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            candidate.isSelected ? Color.green.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}

private struct PanoramaInspectorStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CleanupResultBanner: View {
    let result: CleanupExecutionResult
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(result.failures.isEmpty ? Color.green.opacity(0.14) : Color.orange.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: result.failures.isEmpty ? "checkmark" : "exclamationmark.triangle.fill")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(result.failures.isEmpty ? .green : .orange)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("已移入废纸篓 \(result.cleaned.count) 项")
                    .font(.callout.weight(.bold))
                Text("释放约 \(ByteFormat.string(result.cleanedBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !result.failures.isEmpty {
                Spacer()
                Text("失败 \(result.failures.count) 项")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(result.failures.isEmpty ? Color.green.opacity(colorScheme == .dark ? 0.08 : 0.06) : Color.orange.opacity(colorScheme == .dark ? 0.08 : 0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(result.failures.isEmpty ? Color.green.opacity(0.2) : Color.orange.opacity(0.2), lineWidth: 0.5)
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
        if let command = item.command {
            Divider()
            Button("复制建议命令") {
                copyCommand(command)
            }
        }
    }
}

private struct RiskBadge: View {
    let risk: RiskLevel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.foreground)
                .frame(width: 6, height: 6)
            Text(risk.label)
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color.foreground)
        .background(color.background, in: Capsule())
    }

    private var color: (background: Color, foreground: Color) {
        let isDark = colorScheme == .dark
        switch risk {
        case .safeClean:
            return (Color.green.opacity(isDark ? 0.22 : 0.14), Color.green)
        case .review:
            return (Color.orange.opacity(isDark ? 0.25 : 0.16), Color.orange)
        case .keep:
            return (Color.gray.opacity(isDark ? 0.22 : 0.14), .secondary)
        case .system:
            return (Color.blue.opacity(isDark ? 0.22 : 0.14), Color.blue)
        }
    }
}
