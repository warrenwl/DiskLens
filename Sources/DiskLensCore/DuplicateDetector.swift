import CryptoKit
import Foundation

public struct DuplicateGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: String { files.first?.path ?? UUID().uuidString }
    public var fileSizeBytes: Int64
    public var files: [DuplicateFileEntry]
    public var wastedBytes: Int64 { fileSizeBytes * Int64(max(files.count - 1, 0)) }
}

public struct DuplicateFileEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var sizeBytes: Int64
    public var category: ItemCategory
    public var risk: RiskLevel
}

public struct DuplicateResult: Codable, Equatable, Sendable {
    public var groups: [DuplicateGroup]
    public var totalWastedBytes: Int64
    public var totalDuplicateFiles: Int
    public var scannedFilesCount: Int
    public var scanDurationSeconds: TimeInterval
}

public struct DuplicateProgress: Codable, Equatable, Sendable {
    public var phase: DuplicatePhase
    public var completedFiles: Int
    public var totalFiles: Int

    public enum DuplicatePhase: String, Codable, Sendable {
        case collecting = "收集文件"
        case sizeGrouping = "按大小分组"
        case hashing = "计算哈希"
        case done = "完成"
    }
}

public enum DuplicateDetector: Sendable {
    private static let minFileSize: Int64 = 1_000_000

    public static func detect(
        in items: [ScanItem],
        onProgress: (@Sendable (DuplicateProgress) -> Void)? = nil
    ) async -> DuplicateResult {
        let startedAt = Date()

        let allFiles = items.flatMap { RecommendationEngine.flatten($0) }
            .filter { $0.kind == .file && $0.sizeBytes >= minFileSize }
        onProgress?(.init(phase: .collecting, completedFiles: 0, totalFiles: allFiles.count))

        struct SizeKey: Hashable {
            let name: String
            let size: Int64
        }
        let sizeGroups = Dictionary(grouping: allFiles) { SizeKey(name: $0.name, size: $0.sizeBytes) }
            .filter { $0.value.count > 1 }
        onProgress?(.init(phase: .sizeGrouping, completedFiles: allFiles.count, totalFiles: allFiles.count))

        var confirmedGroups: [DuplicateGroup] = []
        let candidates = Array(sizeGroups.values)
        let batchSize = 8
        var batchStart = 0

        while batchStart < candidates.count {
            if Task.isCancelled { break }
            let batchEnd = min(batchStart + batchSize, candidates.count)
            let batch = candidates[batchStart..<batchEnd]

            await withTaskGroup(of: [DuplicateFileEntry]?.self) { group in
                for candidateGroup in batch {
                    group.addTask {
                        var hashGroups: [String: [DuplicateFileEntry]] = [:]
                        for item in candidateGroup {
                            if Task.isCancelled { return nil }
                            if let hash = fullSHA256(path: item.path) {
                                let entry = DuplicateFileEntry(
                                    path: item.path, name: item.name,
                                    sizeBytes: item.sizeBytes, category: item.category, risk: item.risk
                                )
                                hashGroups[hash, default: []].append(entry)
                            }
                        }
                        let dup = hashGroups.values.filter { $0.count > 1 }
                        return dup.isEmpty ? nil : dup.first!
                    }
                }
                for await result in group {
                    if let entries = result {
                        confirmedGroups.append(DuplicateGroup(
                            fileSizeBytes: entries.first!.sizeBytes, files: entries
                        ))
                    }
                }
            }

            let completed = min(batchEnd, candidates.count)
            onProgress?(.init(phase: .hashing, completedFiles: completed, totalFiles: candidates.count))
            batchStart = batchEnd
        }

        confirmedGroups.sort { $0.wastedBytes > $1.wastedBytes }
        let totalWasted = confirmedGroups.reduce(Int64(0)) { $0 + $1.wastedBytes }
        let totalDupFiles = confirmedGroups.reduce(0) { $0 + $1.files.count }

        onProgress?(.init(phase: .done, completedFiles: candidates.count, totalFiles: candidates.count))

        return DuplicateResult(
            groups: confirmedGroups,
            totalWastedBytes: totalWasted,
            totalDuplicateFiles: totalDupFiles,
            scannedFilesCount: allFiles.count,
            scanDurationSeconds: Date().timeIntervalSince(startedAt)
        )
    }

    private static func fullSHA256(path: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 4_000_000), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let hash = hasher.finalize()
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
