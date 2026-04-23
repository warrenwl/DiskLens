import AppKit
import Foundation

public enum ReportExporter {
    public static func jsonData(for result: ScanResult) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(result)
    }

    public static func markdown(for result: ScanResult) -> String {
        var lines: [String] = []
        lines.append("# DiskLens 磁盘扫描报告")
        lines.append("")
        lines.append("- Schema 版本：\(result.schemaVersion)")
        lines.append("- 扫描时间：\(DateFormatter.report.string(from: result.summary.scannedAt))")
        lines.append("- 扫描模式：\(result.summary.mode.label)")
        lines.append("- 扫描耗时：\(duration(result.summary.scanDurationSeconds))")
        lines.append("- 磁盘总量：\(ByteFormat.string(result.summary.totalBytes))")
        lines.append("- 已用空间：\(ByteFormat.string(result.summary.usedBytes))")
        lines.append("- 可用空间：\(ByteFormat.string(result.summary.availableBytes))")
        lines.append("- 本次扫描范围合计：\(ByteFormat.string(result.summary.scannedBytes))")
        lines.append("- 无法读取项目：\(result.summary.inaccessibleCount)")
        lines.append("- 建议可回收空间汇总：\(ByteFormat.string(result.recommendations.reduce(Int64(0)) { $0 + $1.estimatedBytes }))")
        if result.summary.isCancelled {
            lines.append("- 状态：扫描已取消，报告基于部分结果")
        }
        if !result.summary.inaccessiblePaths.isEmpty {
            lines.append("")
            lines.append("## 不可读路径摘要")
            lines.append("")
            for path in result.summary.inaccessiblePaths.prefix(20) {
                lines.append("- `\(path)`")
            }
            if result.summary.inaccessiblePaths.count > 20 {
                lines.append("- 另有 \(result.summary.inaccessiblePaths.count - 20) 项未列出")
            }
        }
        lines.append("")
        lines.append("## 最大占用")
        lines.append("")
        lines.append("| 路径 | 大小 | 分类 | 风险 | 建议 |")
        lines.append("| --- | ---: | --- | --- | --- |")
        for item in RecommendationEngine.flattenedTopItems(result.items, limit: 25) {
            let action = item.command.map { "\(item.recommendedAction)<br>`\($0)`" } ?? item.recommendedAction
            lines.append("| `\(item.path)` | \(ByteFormat.string(item.sizeBytes)) | \(item.category.label) | \(item.risk.label) | \(action) |")
        }
        lines.append("")
        lines.append("## Top 大目录")
        lines.append("")
        lines.append("| 路径 | 大小 | 风险 |")
        lines.append("| --- | ---: | --- |")
        for item in RecommendationEngine.flattenedTopItems(result.items, limit: 40).filter({ $0.kind == .directory }).prefix(20) {
            lines.append("| `\(item.path)` | \(ByteFormat.string(item.sizeBytes)) | \(item.risk.label) |")
        }
        lines.append("")
        lines.append("## 清理建议")
        lines.append("")
        for recommendation in result.recommendations {
            lines.append("### \(recommendation.title)")
            lines.append("")
            lines.append("- 路径：`\(recommendation.affectedPath)`")
            lines.append("- 预计可回收：\(ByteFormat.string(recommendation.estimatedBytes))")
            lines.append("- 风险：\(recommendation.risk.label)")
            if let command = recommendation.command {
                lines.append("- 命令：`\(command)`")
            }
            lines.append("- 步骤：\(recommendation.steps)")
            if !recommendation.rationale.isEmpty {
                lines.append("- 判断依据：\(recommendation.rationale)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func svg(for result: ScanResult, width: Double = 1600, height: Double = 1000) -> String {
        let contentHeight = height - 180
        let rects = TreemapLayout.layout(items: result.items, width: width - 80, height: contentHeight)
        var lines: [String] = []
        lines.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(Int(width))\" height=\"\(Int(height))\" viewBox=\"0 0 \(Int(width)) \(Int(height))\">")
        lines.append("<rect width=\"100%\" height=\"100%\" fill=\"#fbfaf7\"/>")
        lines.append("<style>text{font-family:-apple-system,BlinkMacSystemFont,\"PingFang SC\",Arial,sans-serif;letter-spacing:0}</style>")
        lines.append("<text x=\"40\" y=\"58\" font-size=\"30\" font-weight=\"800\" fill=\"#101418\">DiskLens 磁盘占用全景图</text>")
        lines.append("<text x=\"40\" y=\"92\" font-size=\"15\" font-weight=\"500\" fill=\"#4c5663\">扫描模式：\(escape(result.summary.mode.label))；本次扫描：\(escape(ByteFormat.string(result.summary.scannedBytes)))；可用：\(escape(ByteFormat.string(result.summary.availableBytes)))</text>")
        lines.append("<text x=\"40\" y=\"122\" font-size=\"13\" fill=\"#68717d\">生成时间：\(escape(DateFormatter.report.string(from: result.summary.scannedAt)))</text>")

        for rect in rects {
            let x = rect.x + 40
            let y = rect.y + 150
            let color = color(for: rect.item.risk)
            lines.append("<rect x=\"\(fmt(x))\" y=\"\(fmt(y))\" width=\"\(fmt(rect.width))\" height=\"\(fmt(rect.height))\" rx=\"7\" fill=\"\(color.fill)\" stroke=\"\(color.stroke)\" stroke-width=\"1.4\"/>")
            guard rect.width > 110, rect.height > 58 else { continue }
            lines.append("<text x=\"\(fmt(x + 10))\" y=\"\(fmt(y + 24))\" font-size=\"13\" font-weight=\"700\" fill=\"#101418\">\(escape(fitted(rect.item.name, width: rect.width, fontSize: 13)))</text>")
            lines.append("<text x=\"\(fmt(x + 10))\" y=\"\(fmt(y + 44))\" font-size=\"12\" fill=\"#323942\">\(escape(ByteFormat.string(rect.item.sizeBytes))) · \(escape(rect.item.risk.label))</text>")
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }

    public static func pngData(for result: ScanResult, size: CGSize = CGSize(width: 1600, height: 1000)) -> Data? {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 0.984, green: 0.980, blue: 0.969, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        let title = "DiskLens 磁盘占用全景图" as NSString
        title.draw(
            at: CGPoint(x: 40, y: size.height - 72),
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 30), .foregroundColor: NSColor.black]
        )
        let subtitle = "扫描模式：\(result.summary.mode.label)；本次扫描：\(ByteFormat.string(result.summary.scannedBytes))；可用：\(ByteFormat.string(result.summary.availableBytes))" as NSString
        subtitle.draw(
            at: CGPoint(x: 40, y: size.height - 108),
            withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.darkGray]
        )

        let rects = TreemapLayout.layout(items: result.items, width: Double(size.width - 80), height: Double(size.height - 180))
        for rect in rects {
            let color = nsColor(for: rect.item.risk)
            let drawRect = NSRect(
                x: rect.x + 40,
                y: 30 + rect.y,
                width: max(rect.width - 2, 0),
                height: max(rect.height - 2, 0)
            )
            color.fill.setFill()
            color.stroke.setStroke()
            let path = NSBezierPath(roundedRect: drawRect, xRadius: 7, yRadius: 7)
            path.fill()
            path.lineWidth = 1.4
            path.stroke()

            guard rect.width > 130, rect.height > 60 else { continue }
            let label = fitted(rect.item.name, width: rect.width, fontSize: 13) as NSString
            label.draw(
                at: CGPoint(x: drawRect.minX + 10, y: drawRect.maxY - 28),
                withAttributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.black]
            )
            let sizeText = "\(ByteFormat.string(rect.item.sizeBytes)) · \(rect.item.risk.label)" as NSString
            sizeText.draw(
                at: CGPoint(x: drawRect.minX + 10, y: drawRect.maxY - 48),
                withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.darkGray]
            )
        }

        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func color(for risk: RiskLevel) -> (fill: String, stroke: String) {
        switch risk {
        case .safeClean: return ("#dff5ee", "#1f9d7a")
        case .review: return ("#fff0d7", "#d88a21")
        case .keep: return ("#edf0f4", "#5b6472")
        case .system: return ("#e7e9ee", "#3f4752")
        }
    }

    private static func nsColor(for risk: RiskLevel) -> (fill: NSColor, stroke: NSColor) {
        switch risk {
        case .safeClean:
            return (NSColor(red: 0.875, green: 0.961, blue: 0.933, alpha: 1), NSColor(red: 0.122, green: 0.616, blue: 0.478, alpha: 1))
        case .review:
            return (NSColor(red: 1.000, green: 0.941, blue: 0.843, alpha: 1), NSColor(red: 0.847, green: 0.541, blue: 0.129, alpha: 1))
        case .keep:
            return (NSColor(red: 0.929, green: 0.941, blue: 0.957, alpha: 1), NSColor(red: 0.357, green: 0.392, blue: 0.447, alpha: 1))
        case .system:
            return (NSColor(red: 0.906, green: 0.914, blue: 0.933, alpha: 1), NSColor(red: 0.247, green: 0.278, blue: 0.322, alpha: 1))
        }
    }

    private static func fitted(_ text: String, width: Double, fontSize: Double) -> String {
        let maxChars = max(Int((width - 20) / (fontSize * 0.62)), 0)
        guard maxChars > 3, text.count > maxChars else { return text }
        return String(text.prefix(maxChars - 1)) + "…"
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds)) 秒"
        }
        return "\(Int(seconds / 60)) 分 \(Int(seconds.truncatingRemainder(dividingBy: 60))) 秒"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

public extension RecommendationEngine {
    static func flattenedTopItems(_ roots: [ScanItem], limit: Int) -> [ScanItem] {
        roots
            .flatMap { flatten($0) }
            .filter { $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(limit)
            .map { $0 }
    }
}

private extension DateFormatter {
    static let report: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
