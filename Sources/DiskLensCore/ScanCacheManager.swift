import Foundation

public enum ScanCacheManager {
    private static let storageDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DiskLens", isDirectory: true)
    }()

    private static let lastScanURL = storageDir.appendingPathComponent("last-scan.json")
    private static let historyURL = storageDir.appendingPathComponent("history.json")
    private static let maxHistoryEntries = 50

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Last Scan Cache

    public static func save(_ result: ScanResult) throws {
        try ensureDirectory()
        let data = try encoder.encode(result)
        try data.write(to: lastScanURL, options: .atomic)
    }

    public static func load() throws -> ScanResult? {
        guard FileManager.default.fileExists(atPath: lastScanURL.path) else { return nil }
        let data = try Data(contentsOf: lastScanURL)
        return try decoder.decode(ScanResult.self, from: data)
    }

    // MARK: - Delta

    public static func computeDelta(old: ScanResult, new: ScanResult) -> ScanDelta {
        let oldFlat = Dictionary(uniqueKeysWithValues: old.items.flatMap { RecommendationEngine.flatten($0) }.map { ($0.path, $0) })
        let newFlat = Dictionary(uniqueKeysWithValues: new.items.flatMap { RecommendationEngine.flatten($0) }.map { ($0.path, $0) })

        var newItems: [DeltaEntry] = []
        var grownItems: [DeltaEntry] = []
        var shrunkItems: [DeltaEntry] = []

        for (path, newItem) in newFlat {
            if let oldItem = oldFlat[path] {
                let oldSize = oldItem.sizeBytes
                let newSize = newItem.sizeBytes
                guard oldSize > 0 else { continue }
                let change = Double(newSize - oldSize) / Double(oldSize) * 100
                let entry = DeltaEntry(
                    path: path, name: newItem.name,
                    oldSizeBytes: oldSize, newSizeBytes: newSize,
                    changePercent: change, category: newItem.category, risk: newItem.risk
                )
                if change > 10 {
                    grownItems.append(entry)
                } else if change < -10 {
                    shrunkItems.append(entry)
                }
            } else {
                newItems.append(DeltaEntry(
                    path: path, name: newItem.name,
                    oldSizeBytes: nil, newSizeBytes: newItem.sizeBytes,
                    changePercent: 0, category: newItem.category, risk: newItem.risk
                ))
            }
        }

        let removedItems: [DeltaEntry] = oldFlat.compactMap { path, oldItem in
            guard newFlat[path] == nil else { return nil }
            return DeltaEntry(
                path: path, name: oldItem.name,
                oldSizeBytes: oldItem.sizeBytes, newSizeBytes: nil,
                changePercent: 0, category: oldItem.category, risk: oldItem.risk
            )
        }

        let sortByAbsChange: (DeltaEntry, DeltaEntry) -> Bool = { abs($0.changePercent) > abs($1.changePercent) }
        return ScanDelta(
            newItems: newItems.sorted(by: { $0.newSizeBytes ?? 0 > $1.newSizeBytes ?? 0 }),
            grownItems: grownItems.sorted(by: sortByAbsChange),
            shrunkItems: shrunkItems.sorted(by: sortByAbsChange),
            removedItems: removedItems.sorted(by: { $0.oldSizeBytes ?? 0 > $1.oldSizeBytes ?? 0 })
        )
    }

    // MARK: - History

    public static func loadHistory() throws -> [ScanSummary] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        let data = try Data(contentsOf: historyURL)
        return try decoder.decode([ScanSummary].self, from: data)
    }

    public static func appendToHistory(_ summary: ScanSummary) throws {
        var history = (try? loadHistory()) ?? []
        history.append(summary)
        if history.count > maxHistoryEntries {
            history = Array(history.suffix(maxHistoryEntries))
        }
        try ensureDirectory()
        let data = try encoder.encode(history)
        try data.write(to: historyURL, options: .atomic)
    }

    // MARK: - Private

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }
}
