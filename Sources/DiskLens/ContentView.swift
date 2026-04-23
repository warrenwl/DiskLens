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

                HStack(alignment: .center, spacing: 34) {
                    VStack(alignment: .leading, spacing: 0) {
                        HomeSignalMark()
                            .padding(.bottom, 34)
                        Text("看清磁盘")
                            .font(.system(size: 52, weight: .bold))
                            .tracking(0)
                        Text("谨慎清理")
                            .font(.system(size: 52, weight: .bold))
                            .tracking(0)
                        Text("用 Treemap 定位空间大户，用复核式清理把安全项目统一移入废纸篓。")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 18)
                            .frame(maxWidth: 620, alignment: .leading)
                        HStack(spacing: 10) {
                            HomeTrustPill(text: "只移入废纸篓", systemImage: "trash")
                            HomeTrustPill(text: "默认保护用户数据", systemImage: "lock.shield")
                            HomeTrustPill(text: "可视化定位", systemImage: "square.grid.3x3")
                        }
                        .padding(.top, 26)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
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
                    }
                    .frame(width: 430)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    model.openHome()
                } label: {
                    Label("首页", systemImage: "chevron.left")
                }

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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
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

            VStack(alignment: .leading, spacing: 2) {
                Text("一键清理")
                    .font(.headline)
                Text("已选 \(model.selectedCleanupCandidates.count) 项，约 \(ByteFormat.string(model.selectedCleanupBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.prepareCleanupPlan()
            } label: {
                Label("重新检索", systemImage: "arrow.clockwise")
            }
            .disabled(model.isPreparingCleanup || model.isExecutingCleanup)

            Button {
                model.requestOneClickCleanup()
            } label: {
                Label(model.isExecutingCleanup ? "清理中" : "一键清理", systemImage: model.isExecutingCleanup ? "hourglass" : "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRunCleanup)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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
                    HStack(spacing: 8) {
                        PanoramaInspectorStat(title: "分类", value: selected.category.label)
                        PanoramaInspectorStat(title: "类型", value: selected.kind.rawValue)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                }
            }
            if model.selectedItem == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "cursorarrow.click")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("点击左侧矩形查看路径详情")
                        .font(.headline)
                    Text("磁盘全景只用于空间观察和定位。清理操作请回到首页进入一键清理。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                }
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

private struct HomeActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.12))
                    Image(systemName: systemImage)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeStatusStrip: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct HomeSignalMark: View {
    var body: some View {
        ZStack(alignment: .center) {
            Circle()
                .fill(Color.green.opacity(0.10))
                .frame(width: 128, height: 128)
            Circle()
                .stroke(Color.green.opacity(0.24), lineWidth: 1)
                .frame(width: 98, height: 98)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 42))
                path.addLine(to: CGPoint(x: 36, y: 42))
                path.addLine(to: CGPoint(x: 49, y: 13))
                path.addLine(to: CGPoint(x: 68, y: 71))
                path.addLine(to: CGPoint(x: 88, y: 32))
                path.addLine(to: CGPoint(x: 105, y: 42))
                path.addLine(to: CGPoint(x: 132, y: 42))
            }
            .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .frame(width: 132, height: 84)
        }
        .frame(width: 150, height: 150)
    }
}

private struct HomeTrustPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.secondary.opacity(0.08), in: Capsule())
    }
}

private struct CleanupSectionView: View {
    let section: CleanupSection
    let toggleSection: () -> Void
    let toggleCandidate: (CleanupCandidate) -> Void
    let revealInFinder: (String) -> Void
    let copyPath: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button(action: toggleSection) {
                    Image(systemName: section.allSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(section.kind.defaultSelected ? .green : .secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: section.kind.systemImage)
                    .foregroundStyle(section.kind.defaultSelected ? .green : .orange)
                    .font(.title3)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.kind.title)
                        .font(.title3.weight(.bold))
                    Text(section.kind.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(section.selectedCount)/\(section.candidates.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(ByteFormat.string(section.selectedBytes))
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            .padding(.bottom, 2)

            if section.candidates.isEmpty {
                Text("暂无候选项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 12)], spacing: 12) {
                    ForEach(section.candidates.prefix(24)) { candidate in
                        CleanupCandidateCard(
                            candidate: candidate,
                            toggle: { toggleCandidate(candidate) },
                            revealInFinder: revealInFinder,
                            copyPath: copyPath
                        )
                    }
                }
                if section.candidates.count > 24 {
                    Text("还有 \(section.candidates.count - 24) 项未显示")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 28)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct CleanupCandidateCard: View {
    let candidate: CleanupCandidate
    let toggle: () -> Void
    let revealInFinder: (String) -> Void
    let copyPath: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: toggle) {
                    Image(systemName: candidate.isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(candidate.isSelected ? .green : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(ByteFormat.string(candidate.sizeBytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RiskBadge(risk: candidate.risk)
            }

            Text(candidate.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(candidate.path)

            Text(candidate.detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button {
                    copyPath(candidate.path)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("复制路径")
                Button {
                    revealInFinder(candidate.path)
                } label: {
                    Image(systemName: "finder")
                }
                .buttonStyle(.borderless)
                .help("Finder 中显示")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(candidate.isSelected ? Color.green.opacity(0.11) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(candidate.isSelected ? Color.green.opacity(0.45) : Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct PanoramaInspectorStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct CleanupResultBanner: View {
    let result: CleanupExecutionResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.failures.isEmpty ? .green : .orange)
            Text("已移入废纸篓 \(result.cleaned.count) 项，约 \(ByteFormat.string(result.cleanedBytes))")
                .font(.callout.weight(.semibold))
            if !result.failures.isEmpty {
                Text("失败 \(result.failures.count) 项")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
