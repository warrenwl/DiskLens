import Foundation

public enum AppLeftoverKind: String, Codable, CaseIterable, Sendable {
    case cache
    case preference
    case log
    case savedState
    case httpStorage
    case appSupport
    case container
    case groupContainer
    case webKit
    case cookie

    public var label: String {
        switch self {
        case .cache: return "缓存"
        case .preference: return "偏好设置"
        case .log: return "日志"
        case .savedState: return "窗口状态"
        case .httpStorage: return "HTTP 存储"
        case .appSupport: return "应用支持数据"
        case .container: return "应用容器"
        case .groupContainer: return "共享容器"
        case .webKit: return "WebKit 数据"
        case .cookie: return "Cookie"
        }
    }
}

public struct AppLeftoverItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var appName: String
    public var bundleIdentifier: String
    public var kind: AppLeftoverKind
    public var risk: RiskLevel
    public var sizeBytes: Int64
    public var path: String
    public var suggestedAction: String

    public var isDefaultSelected: Bool {
        risk == .safeClean
    }
}

public struct AppLeftoverResult: Codable, Equatable, Sendable {
    public var scannedAt: Date
    public var items: [AppLeftoverItem]

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    public var defaultSelectedBytes: Int64 {
        items.filter(\.isDefaultSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    public var safeItemCount: Int {
        items.filter { $0.risk == .safeClean }.count
    }
}

public struct AppLeftoverCleanupResult: Codable, Equatable, Sendable {
    public var cleanedItems: [AppLeftoverItem]
    public var failedItems: [AppLeftoverCleanupFailure]

    public var cleanedBytes: Int64 {
        cleanedItems.reduce(0) { $0 + $1.sizeBytes }
    }
}

public struct AppLeftoverCleanupFailure: Codable, Equatable, Sendable {
    public var item: AppLeftoverItem
    public var message: String
}

public enum AppLeftoverCleaner: Sendable {
    public static func cleanDefaultSelected(_ result: AppLeftoverResult) async -> AppLeftoverCleanupResult {
        await clean(items: result.items.filter(\.isDefaultSelected))
    }

    public static func clean(items: [AppLeftoverItem]) async -> AppLeftoverCleanupResult {
        await Task.detached(priority: .userInitiated) {
            cleanSync(items: items)
        }.value
    }

    private static func cleanSync(items: [AppLeftoverItem]) -> AppLeftoverCleanupResult {
        var cleaned: [AppLeftoverItem] = []
        var failures: [AppLeftoverCleanupFailure] = []
        for item in items where item.isDefaultSelected {
            if Task.isCancelled { break }
            do {
                _ = try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                cleaned.append(item)
            } catch {
                failures.append(AppLeftoverCleanupFailure(item: item, message: error.localizedDescription))
            }
        }
        return AppLeftoverCleanupResult(cleanedItems: cleaned, failedItems: failures)
    }
}

public enum AppLeftoverScanner: Sendable {
    public static func scan() async -> AppLeftoverResult {
        await scan(
            installedAppRoots: defaultInstalledAppRoots(),
            libraryRoots: defaultLibraryRoots()
        )
    }

    public static func scan(
        installedAppRoots: [URL],
        libraryRoots: [URL]
    ) async -> AppLeftoverResult {
        await Task.detached(priority: .userInitiated) {
            scanSync(installedAppRoots: installedAppRoots, libraryRoots: libraryRoots)
        }.value
    }

    private static func scanSync(installedAppRoots: [URL], libraryRoots: [URL]) -> AppLeftoverResult {
        let installed = installedApplications(in: installedAppRoots)
        var items: [AppLeftoverItem] = []
        var seen = Set<String>()
        var orphanIDs = Set<String>()
        var orphanNamesByID: [String: Set<String>] = [:]

        for libraryRoot in libraryRoots {
            let roots = primaryCandidateRoots(in: libraryRoot)
            for root in roots {
                for child in immediateChildren(of: root.url) {
                    guard let bundleID = inferBundleIdentifier(from: child, kind: root.kind),
                          !installed.bundleIDs.contains(bundleID) else {
                        continue
                    }
                    let appName = displayName(for: bundleID)
                    appendItem(
                        url: child,
                        appName: appName,
                        bundleID: bundleID,
                        kind: root.kind,
                        risk: root.risk,
                        to: &items,
                        seen: &seen
                    )
                    orphanIDs.insert(bundleID)
                    orphanNamesByID[bundleID, default: []].insert(appName)
                }
            }
        }

        for libraryRoot in libraryRoots {
            appendNameMatchedItems(
                libraryRoot: libraryRoot,
                orphanIDs: orphanIDs,
                orphanNamesByID: orphanNamesByID,
                to: &items,
                seen: &seen
            )
        }

        items.sort {
            if $0.risk.sortOrder == $1.risk.sortOrder {
                if $0.sizeBytes == $1.sizeBytes { return $0.path < $1.path }
                return $0.sizeBytes > $1.sizeBytes
            }
            return $0.risk.sortOrder < $1.risk.sortOrder
        }
        return AppLeftoverResult(scannedAt: Date(), items: items)
    }

    private static func appendNameMatchedItems(
        libraryRoot: URL,
        orphanIDs: Set<String>,
        orphanNamesByID: [String: Set<String>],
        to items: inout [AppLeftoverItem],
        seen: inout Set<String>
    ) {
        let appSupport = libraryRoot.appendingPathComponent("Application Support", isDirectory: true)
        let logs = libraryRoot.appendingPathComponent("Logs", isDirectory: true)
        let groupContainers = libraryRoot.appendingPathComponent("Group Containers", isDirectory: true)

        for child in immediateChildren(of: appSupport) {
            guard let match = matchName(child.lastPathComponent, orphanIDs: orphanIDs, namesByID: orphanNamesByID) else {
                continue
            }
            appendItem(url: child, appName: match.name, bundleID: match.id, kind: .appSupport, risk: .review, to: &items, seen: &seen)
        }

        for child in immediateChildren(of: logs) {
            guard let match = matchName(child.lastPathComponent, orphanIDs: orphanIDs, namesByID: orphanNamesByID) else {
                continue
            }
            appendItem(url: child, appName: match.name, bundleID: match.id, kind: .log, risk: .safeClean, to: &items, seen: &seen)
        }

        for child in immediateChildren(of: groupContainers) {
            guard let match = matchContainedIdentifier(child.lastPathComponent, orphanIDs: orphanIDs, namesByID: orphanNamesByID) else {
                continue
            }
            appendItem(url: child, appName: match.name, bundleID: match.id, kind: .groupContainer, risk: .keep, to: &items, seen: &seen)
        }
    }

    private static func appendItem(
        url: URL,
        appName: String,
        bundleID: String,
        kind: AppLeftoverKind,
        risk: RiskLevel,
        to items: inout [AppLeftoverItem],
        seen: inout Set<String>
    ) {
        let path = url.path
        guard seen.insert(path).inserted else { return }
        items.append(
            AppLeftoverItem(
                appName: appName,
                bundleIdentifier: bundleID,
                kind: kind,
                risk: risk,
                sizeBytes: allocatedSize(for: url),
                path: path,
                suggestedAction: action(for: kind, risk: risk)
            )
        )
    }

    private static func primaryCandidateRoots(in libraryRoot: URL) -> [(url: URL, kind: AppLeftoverKind, risk: RiskLevel)] {
        [
            (libraryRoot.appendingPathComponent("Caches", isDirectory: true), .cache, .safeClean),
            (libraryRoot.appendingPathComponent("Preferences", isDirectory: true), .preference, .safeClean),
            (libraryRoot.appendingPathComponent("Saved Application State", isDirectory: true), .savedState, .safeClean),
            (libraryRoot.appendingPathComponent("HTTPStorages", isDirectory: true), .httpStorage, .safeClean),
            (libraryRoot.appendingPathComponent("Containers", isDirectory: true), .container, .review),
            (libraryRoot.appendingPathComponent("WebKit", isDirectory: true), .webKit, .review),
            (libraryRoot.appendingPathComponent("Cookies", isDirectory: true), .cookie, .review),
        ]
    }

    private static func inferBundleIdentifier(from url: URL, kind: AppLeftoverKind) -> String? {
        let name = url.lastPathComponent
        let candidate: String
        switch kind {
        case .preference:
            guard name.hasSuffix(".plist") else { return nil }
            candidate = String(name.dropLast(".plist".count))
        case .savedState:
            guard name.hasSuffix(".savedState") else { return nil }
            candidate = String(name.dropLast(".savedState".count))
        case .cookie:
            candidate = name.replacingOccurrences(of: ".binarycookies", with: "")
        default:
            candidate = name
        }
        return candidate.contains(".") ? candidate : nil
    }

    private static func matchName(
        _ name: String,
        orphanIDs: Set<String>,
        namesByID: [String: Set<String>]
    ) -> (id: String, name: String)? {
        if orphanIDs.contains(name) {
            return (name, displayName(for: name))
        }
        let normalized = normalize(name)
        for (id, names) in namesByID {
            if names.contains(where: { normalize($0) == normalized }) {
                return (id, displayName(for: id))
            }
        }
        return nil
    }

    private static func matchContainedIdentifier(
        _ name: String,
        orphanIDs: Set<String>,
        namesByID: [String: Set<String>]
    ) -> (id: String, name: String)? {
        for id in orphanIDs where name.contains(id) {
            return (id, displayName(for: id))
        }
        return matchName(name, orphanIDs: orphanIDs, namesByID: namesByID)
    }

    private static func installedApplications(in roots: [URL]) -> (bundleIDs: Set<String>, names: Set<String>) {
        var bundleIDs = Set<String>()
        var names = Set<String>()
        for root in roots {
            for app in appBundles(in: root) {
                guard let metadata = appMetadata(from: app) else { continue }
                bundleIDs.insert(metadata.bundleID)
                names.formUnion(metadata.names)
            }
        }
        return (bundleIDs, names)
    }

    private static func appBundles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return enumerator.compactMap { entry in
            guard let url = entry as? URL, url.pathExtension == "app" else { return nil }
            return url
        }
    }

    private static func appMetadata(from appURL: URL) -> (bundleID: String, names: Set<String>)? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String else {
            return nil
        }
        let names = [
            plist["CFBundleDisplayName"] as? String,
            plist["CFBundleName"] as? String,
            plist["CFBundleExecutable"] as? String,
            Optional(appURL.deletingPathExtension().lastPathComponent),
        ].compactMap { $0 }.filter { !$0.isEmpty }
        return (bundleID, Set(names))
    }

    private static func immediateChildren(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func allocatedSize(for url: URL) -> Int64 {
        var total = singleAllocatedSize(for: url)
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == true,
              let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return total
        }
        for case let child as URL in enumerator {
            if Task.isCancelled { break }
            total += singleAllocatedSize(for: child)
        }
        return total
    }

    private static func singleAllocatedSize(for url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
            return 0
        }
        if let total = values.totalFileAllocatedSize { return Int64(total) }
        if let file = values.fileAllocatedSize { return Int64(file) }
        return 0
    }

    private static func action(for kind: AppLeftoverKind, risk: RiskLevel) -> String {
        switch risk {
        case .safeClean:
            return "可移动到废纸篓；通常不会影响用户数据"
        case .review:
            return kind == .appSupport ? "可能包含用户数据，清理前先复核" : "需确认来源后再清理"
        case .keep, .system:
            return "高风险路径，第一版只展示不自动清理"
        }
    }

    private static func displayName(for bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: " ", with: "")
    }

    private static func defaultInstalledAppRoots() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications"),
        ]
    }

    private static func defaultLibraryRoots() -> [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true),
        ]
    }
}
