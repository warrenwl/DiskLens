import DiskLensCore
import SwiftUI

struct TreemapPanel: View {
    let items: [ScanItem]
    let title: String
    let breadcrumbs: [(label: String, path: String?)]
    let selectedItem: ScanItem?
    let selectedPath: String?
    let treemapRootPath: String?
    let loadingPath: String?
    let onSelect: (ScanItem) -> Void
    let onEnter: (ScanItem) -> Void
    let onBreadcrumb: (String?) -> Void
    @State private var hoveredItem: ScanItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Legend()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            onBreadcrumb(crumb.path)
                        } label: {
                            Text(crumb.label)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(index == breadcrumbs.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == breadcrumbs.count - 1 ? .primary : .secondary)
                    }
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(nsColor: .textBackgroundColor))
                        .allowsHitTesting(false)
                    TreemapCanvas(
                        items: items,
                        rect: CGRect(origin: .zero, size: proxy.size),
                        selectedPath: selectedPath,
                        hoveredPath: hoveredItem?.path,
                        loadingPath: loadingPath,
                        onSelect: onSelect,
                        onEnter: onEnter,
                        onHover: { hoveredItem = $0 }
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                )
            }
            HoverStatusBar(item: hoveredItem)
            SelectedInspector(
                item: selectedItem,
                isLoading: loadingPath == selectedItem?.path,
                isCurrentRoot: selectedItem?.path == treemapRootPath,
                onEnter: {
                    if let item = selectedItem {
                        onEnter(item)
                    }
                }
            )
        }
        .padding(16)
    }
}

private struct TreemapCanvas: View {
    let items: [ScanItem]
    let rect: CGRect
    let selectedPath: String?
    let hoveredPath: String?
    let loadingPath: String?
    let onSelect: (ScanItem) -> Void
    let onEnter: (ScanItem) -> Void
    let onHover: (ScanItem?) -> Void

    var body: some View {
        let layout = TreemapLayout.layout(
            items: items,
            x: Double(rect.minX),
            y: Double(rect.minY),
            width: Double(rect.width),
            height: Double(rect.height)
        )

        ForEach(layout, id: \.item.id) { node in
            let nodeRect = CGRect(x: node.x, y: node.y, width: max(node.width, 0), height: max(node.height, 0))
            TreemapCell(
                item: node.item,
                rect: nodeRect,
                isSelected: selectedPath == node.item.path,
                isHovered: hoveredPath == node.item.path,
                isLoading: loadingPath == node.item.path,
                onSelect: onSelect,
                onEnter: onEnter,
                onHover: onHover
            )
        }
    }
}

private struct TreemapCell: View {
    let item: ScanItem
    let rect: CGRect
    let isSelected: Bool
    let isHovered: Bool
    let isLoading: Bool
    let onSelect: (ScanItem) -> Void
    let onEnter: (ScanItem) -> Void
    let onHover: (ScanItem?) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(cellFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(cellStroke, lineWidth: cellLineWidth)
                )
                .shadow(color: cellShadowColor, radius: cellShadowRadius, x: 0, y: 3)
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 4)
                    .blur(radius: 2)
                    .allowsHitTesting(false)
            }
            if isHovered {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .allowsHitTesting(false)
            }
            if rect.width > 96, rect.height > 42 {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ByteFormat.string(item.sizeBytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if rect.width > 190, rect.height > 74 {
                        Text(cellHint)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(riskColor)
                            .lineLimit(1)
                    }
                }
                .padding(9)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .contentShape(Rectangle())
        .help("\(item.path)\n\(ByteFormat.string(item.sizeBytes))\n\(item.recommendedAction)")
        .offset(x: rect.minX, y: rect.minY)
        .zIndex(isHovered ? 2 : (isSelected ? 1 : 0))
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onTapGesture {
            onSelect(item)
        }
        .onTapGesture(count: 2) {
            onEnter(item)
        }
        .onHover { inside in
            onHover(inside ? item : nil)
        }
    }

    private var cellHint: String {
        if isLoading {
            return "加载中..."
        }
        if item.kind == .directory {
            return item.children.isEmpty ? "双击加载下一层" : "\(item.children.count) 项 · 双击进入"
        }
        return item.risk.label
    }

    private var riskColor: Color {
        switch item.risk {
        case .safeClean: return .green
        case .review: return .orange
        case .keep: return .gray
        case .system: return .blue
        }
    }

    private var cellFill: Color {
        if isHovered { return riskColor.opacity(0.32) }
        if isSelected { return riskColor.opacity(0.25) }
        return riskColor.opacity(0.14)
    }

    private var cellStroke: Color {
        if isHovered { return riskColor }
        if isSelected { return Color.accentColor }
        return riskColor.opacity(0.70)
    }

    private var cellLineWidth: CGFloat {
        if isSelected { return 3.0 }
        if isHovered { return 2.2 }
        return 1.2
    }

    private var cellShadowColor: Color {
        if isSelected { return Color.accentColor.opacity(0.35) }
        if isHovered { return riskColor.opacity(0.35) }
        return .clear
    }

    private var cellShadowRadius: CGFloat {
        (isSelected || isHovered) ? 10 : 0
    }
}

private struct HoverStatusBar: View {
    let item: ScanItem?

    var body: some View {
        HStack(spacing: 10) {
            if let item {
                Label(item.name, systemImage: item.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(minWidth: 120, alignment: .leading)
                Text(item.kind.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
                Text(item.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Text(ByteFormat.string(item.sizeBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                RiskMiniLabel(risk: item.risk)
            } else {
                Text("悬停：无。把鼠标移到矩形上查看对应文件夹路径。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .frame(minHeight: 26)
    }
}
private struct SelectedInspector: View {
    let item: ScanItem?
    let isLoading: Bool
    let isCurrentRoot: Bool
    let onEnter: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let item {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已选中：\(item.name)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(item.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.recommendedAction)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(ByteFormat.string(item.sizeBytes))
                    .monospacedDigit()
                RiskMiniLabel(risk: item.risk)
                if item.kind == .directory && !isCurrentRoot {
                    Button {
                        onEnter()
                    } label: {
                        Label(isLoading ? "加载中" : "进入", systemImage: isLoading ? "hourglass" : "arrow.down.right.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
                    .help("加载并进入这个目录的下一层")
                }
            } else {
                Text("移动鼠标只显示悬停预览；单击矩形才会选中，双击或点「进入」加载下一层。")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .frame(minHeight: 34)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private extension ItemKind {
    var label: String {
        switch self {
        case .file: return "文件"
        case .directory: return "文件夹"
        case .symlink: return "符号链接"
        case .inaccessible: return "不可读"
        }
    }

    var systemImage: String {
        switch self {
        case .file: return "doc"
        case .directory: return "folder"
        case .symlink: return "link"
        case .inaccessible: return "lock"
        }
    }
}

private struct RiskMiniLabel: View {
    let risk: RiskLevel

    var body: some View {
        Text(risk.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch risk {
        case .safeClean: return .green
        case .review: return .orange
        case .keep: return .gray
        case .system: return .blue
        }
    }
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 10) {
            LegendDot(color: .green, label: "可清")
            LegendDot(color: .orange, label: "谨慎")
            LegendDot(color: .gray, label: "保留")
            LegendDot(color: .blue, label: "系统")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.75))
                .frame(width: 7, height: 7)
            Text(label)
        }
    }
}
