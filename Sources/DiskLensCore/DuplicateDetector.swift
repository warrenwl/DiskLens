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
        case quickHashing = "快速哈希"
        case fullHashing = "完整哈希"
        case done = "完成"
    }
}

public enum DuplicateDetector: Sendable {
    private static let minFileSize: Int64 = 1_000_000
    private static let sampleSize = 1_000_000

    public static func detect(
        in items: [ScanItem],
        onProgress: (@Sendable (DuplicateProgress) -> Void)? = nil
    ) async -> DuplicateResult {
        let startedAt = Date()

        let allFiles = items.flatMap { RecommendationEngine.flatten($0) }
            .filter { $0.kind == .file && $0.sizeBytes >= minFileSize }
        onProgress?(.init(phase: .collecting, completedFiles: 0, totalFiles: allFiles.count))

        let sizeGroups = Dictionary(grouping: allFiles) { $0.sizeBytes }
            .filter { $0.value.count > 1 }
        onProgress?(.init(phase: .sizeGrouping, completedFiles: allFiles.count, totalFiles: allFiles.count))

        var confirmedGroups: [DuplicateGroup] = []
        let candidates = Array(sizeGroups.values)
        let batchSize = 8
        var batchStart = 0
        onProgress?(.init(phase: .quickHashing, completedFiles: 0, totalFiles: candidates.count))

        while batchStart < candidates.count {
            if Task.isCancelled { break }
            let batchEnd = min(batchStart + batchSize, candidates.count)
            let batch = candidates[batchStart..<batchEnd]

            await withTaskGroup(of: [DuplicateGroup].self) { group in
                for candidateGroup in batch {
                    group.addTask {
                        var quickGroups: [String: [ScanItem]] = [:]
                        for item in candidateGroup {
                            if Task.isCancelled { return [] }
                            if let hash = sampledSHA256(path: item.path, sizeBytes: item.sizeBytes) {
                                quickGroups[hash, default: []].append(item)
                            }
                        }

                        var confirmedGroups: [DuplicateGroup] = []
                        for quickGroup in quickGroups.values where quickGroup.count > 1 {
                            if Task.isCancelled { return confirmedGroups }
                            var fullGroups: [String: [DuplicateFileEntry]] = [:]
                            for item in quickGroup {
                                if Task.isCancelled { return confirmedGroups }
                                if let hash = fullSHA256(path: item.path) {
                                    fullGroups[hash, default: []].append(entry(from: item))
                                }
                            }
                            confirmedGroups.append(contentsOf: fullGroups.values
                                .filter { $0.count > 1 }
                                .map { entries in
                                    DuplicateGroup(fileSizeBytes: entries.first?.sizeBytes ?? 0, files: entries)
                                })
                        }
                        return confirmedGroups
                    }
                }
                for await result in group {
                    confirmedGroups.append(contentsOf: result)
                }
            }

            let completed = min(batchEnd, candidates.count)
            onProgress?(.init(phase: .fullHashing, completedFiles: completed, totalFiles: candidates.count))
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

    private static func entry(from item: ScanItem) -> DuplicateFileEntry {
        DuplicateFileEntry(
            path: item.path,
            name: item.name,
            sizeBytes: item.sizeBytes,
            category: item.category,
            risk: item.risk
        )
    }

    private static func sampledSHA256(path: String, sizeBytes: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        guard let head = try? handle.read(upToCount: sampleSize) else { return nil }
        hasher.update(data: head)

        if sizeBytes > Int64(sampleSize * 2) {
            do {
                try handle.seek(toOffset: UInt64(sizeBytes - Int64(sampleSize)))
                if let tail = try handle.read(upToCount: sampleSize) {
                    hasher.update(data: tail)
                }
            } catch {
                return nil
            }
        }

        return hex(hasher.finalize())
    }

    private static func fullSHA256(path: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 4_000_000), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
