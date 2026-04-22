import DiskLensCore
import SwiftUI

struct DuplicatePanel: View {
    let result: DuplicateResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(.orange)
                Text("重复文件")
                    .font(.headline)
                if result.groups.isEmpty {
                    Text("未发现重复文件")
                        .foregroundStyle(.green)
                } else {
                    Text("浪费 \(ByteFormat.string(result.totalWastedBytes))，共 \(result.totalDuplicateFiles) 个")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("已扫描 \(result.scannedFilesCount) 个文件（≥1MB），耗时 \(formatDuration(result.scanDurationSeconds))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !result.groups.isEmpty {
                Divider()
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(result.groups) { group in
                            DuplicateGroupRow(group: group)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "<1秒" }
        if seconds < 60 { return "\(Int(seconds))秒" }
        return "\(Int(seconds / 60))m\(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
    }
}

private struct DuplicateGroupRow: View {
    let group: DuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(group.files.first?.name ?? "")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(ByteFormat.string(group.fileSizeBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("×\(group.files.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("浪费 \(ByteFormat.string(group.wastedBytes))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
            ForEach(group.files) { file in
                Text(file.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }
}
