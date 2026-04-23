import DiskLensCore
import SwiftUI

struct AppLeftoverPanel: View {
    let result: AppLeftoverResult
    let cleanupResult: AppLeftoverCleanupResult?
    let isCleaning: Bool
    let cleanDefaultSelected: () -> Void
    let copyPath: (String) -> Void
    let revealInFinder: (String) -> Void

    private var groupedItems: [(risk: RiskLevel, items: [AppLeftoverItem])] {
        RiskLevel.allCases.compactMap { risk in
            let items = result.items.filter { $0.risk == risk }
            return items.isEmpty ? nil : (risk, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "app.badge.checkmark")
                    .foregroundStyle(.blue)
                Text("卸载残留")
                    .font(.headline)
                if result.items.isEmpty {
                    Text("未发现高置信残留")
                        .foregroundStyle(.green)
                } else {
                    Text("发现 \(result.items.count) 项，默认可清理 \(ByteFormat.string(result.defaultSelectedBytes))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if result.defaultSelectedBytes > 0 {
                    Button {
                        cleanDefaultSelected()
                    } label: {
                        Label(isCleaning ? "清理中" : "移入废纸篓", systemImage: isCleaning ? "hourglass" : "trash")
                    }
                    .controlSize(.small)
                    .disabled(isCleaning)
                } else {
                    Text("没有默认可清理项")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if let cleanupResult {
                HStack(spacing: 8) {
                    Image(systemName: cleanupResult.failedItems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(cleanupResult.failedItems.isEmpty ? .green : .orange)
                    Text("已移入废纸篓 \(cleanupResult.cleanedItems.count) 项，释放约 \(ByteFormat.string(cleanupResult.cleanedBytes))")
                    if !cleanupResult.failedItems.isEmpty {
                        Text("失败 \(cleanupResult.failedItems.count) 项")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !result.items.isEmpty {
                Divider()
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(groupedItems, id: \.risk) { group in
                            leftoverGroup(group.risk, items: group.items)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func leftoverGroup(_ risk: RiskLevel, items: [AppLeftoverItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                LeftoverRiskBadge(risk: risk)
                Text("\(items.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormat.string(items.reduce(Int64(0)) { $0 + $1.sizeBytes }))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(items.prefix(8)) { item in
                leftoverRow(item)
            }
            if items.count > 8 {
                Text("还有 \(items.count - 8) 项未显示，可在表格中搜索 bundle id 或路径")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func leftoverRow(_ item: AppLeftoverItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.appName)
                        .font(.caption.weight(.semibold))
                    Text(item.kind.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(item.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.path)
            }
            Spacer()
            Text(ByteFormat.string(item.sizeBytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Menu {
                Button("复制路径") { copyPath(item.path) }
                Button("Finder 中显示") { revealInFinder(item.path) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
    }
}

private struct LeftoverRiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Text(risk.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var background: Color {
        switch risk {
        case .safeClean: return .green.opacity(0.16)
        case .review: return .orange.opacity(0.18)
        case .keep: return .gray.opacity(0.16)
        case .system: return .blue.opacity(0.16)
        }
    }

    private var foreground: Color {
        switch risk {
        case .safeClean: return .green
        case .review: return .orange
        case .keep: return .secondary
        case .system: return .blue
        }
    }
}
