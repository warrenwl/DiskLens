import Charts
import DiskLensCore
import SwiftUI

struct ScanHistoryView: View {
    let history: [ScanSummary]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("扫描历史")
                    .font(.title2.weight(.bold))
                Spacer()
                Text("\(history.count) 条记录")
                    .foregroundStyle(.secondary)
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            if history.count >= 2 {
                historyChart
            } else {
                Text("至少需要 2 次扫描才能显示趋势")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            Divider()

            historyList
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 480)
    }

    private var historyChart: some View {
        Chart {
            ForEach(history) { entry in
                LineMark(
                    x: .value("时间", entry.scannedAt),
                    y: .value("已用", Double(entry.usedBytes))
                )
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 2))

                LineMark(
                    x: .value("时间", entry.scannedAt),
                    y: .value("可用", Double(entry.availableBytes))
                )
                .foregroundStyle(Color.green)
                .lineStyle(StrokeStyle(lineWidth: 2))

                LineMark(
                    x: .value("时间", entry.scannedAt),
                    y: .value("扫描范围", Double(entry.scannedBytes))
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 2]))
            }
        }
        .chartYAxisLabel("空间")
        .chartLegend(position: .bottom, spacing: 16) {
            HStack(spacing: 16) {
                LegendItem(color: .orange, label: "已用空间")
                LegendItem(color: .green, label: "可用空间")
                LegendItem(color: .blue, label: "扫描范围")
            }
            .font(.caption)
        }
        .frame(height: 220)
    }

    private var historyList: some View {
        Table(Array(history.reversed())) {
            TableColumn("时间") { entry in
                Text(entry.scannedAt, format: .dateTime.year().month().day().hour().minute())
            }
            .width(min: 140, ideal: 160)

            TableColumn("模式") { entry in
                Text(entry.mode.label)
            }
            .width(min: 80, ideal: 100)

            TableColumn("已用") { entry in
                Text(ByteFormat.string(entry.usedBytes))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("可用") { entry in
                Text(ByteFormat.string(entry.availableBytes))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("扫描范围") { entry in
                Text(ByteFormat.string(entry.scannedBytes))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("耗时") { entry in
                Text(formatDuration(entry.scanDurationSeconds))
            }
            .width(min: 60, ideal: 80)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))秒" }
        let m = Int(seconds / 60)
        let s = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(m)m\(s)s"
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}
