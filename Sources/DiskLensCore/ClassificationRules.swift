import Foundation

public struct ClassificationResult: Equatable, Sendable {
    public var category: ItemCategory
    public var risk: RiskLevel
    public var recommendedAction: String
    public var detail: String
    public var reclaimableRatio: Double
}

public enum ClassificationRules {
    public static func classify(path rawPath: String, kind: ItemKind, sizeBytes: Int64) -> ClassificationResult {
        let path = rawPath.standardizedPathForRules
        let lower = path.lowercased()
        let last = URL(fileURLWithPath: path).lastPathComponent.lowercased()

        if !kind.isReadableKind {
            return ClassificationResult(
                category: .protectedData,
                risk: .keep,
                recommendedAction: "需要完全磁盘访问权限后再判断",
                detail: "当前无法读取，先不要按 0 空间处理。",
                reclaimableRatio: 0
            )
        }

        if lower.hasPrefix("/system/") ||
            lower.hasPrefix("/private/var/") ||
            lower.hasPrefix("/var/") ||
            lower == "/private" ||
            lower == "/private/var" ||
            lower == "/var" {
            return ClassificationResult(
                category: .systemData,
                risk: .system,
                recommendedAction: "保留；必要时重启或使用系统设置清理",
                detail: "系统目录不建议手动删除。",
                reclaimableRatio: 0
            )
        }

        if lower.contains("/library/containers/") ||
            lower.contains("/library/group containers/") ||
            lower.contains("/library/keychains") ||
            lower.contains("com.tencent.xinwechat") ||
            lower.contains("com.tencent.qq") ||
            lower.contains("wework") {
            return ClassificationResult(
                category: .protectedData,
                risk: .keep,
                recommendedAction: "保留或在应用内清理",
                detail: "可能包含聊天记录、登录状态、应用数据库。",
                reclaimableRatio: 0
            )
        }

        if lower.contains("/.gemini/antigravity/browser_recordings") {
            return ClassificationResult(
                category: .cache,
                risk: .safeClean,
                recommendedAction: "确认不需要录制历史后可清理",
                detail: "浏览器录制通常可删除，删除前确认没有要回看的记录。",
                reclaimableRatio: 1.0
            )
        }

        if lower.contains("/library/caches") ||
            lower.contains("/.cache/") ||
            lower.contains("/.npm/_cacache") ||
            lower.contains("/.cache/uv") ||
            lower.contains("/pip/cache") ||
            lower.contains("/caches/homebrew") {
            return ClassificationResult(
                category: .cache,
                risk: .safeClean,
                recommendedAction: safeCacheAction(for: lower),
                detail: "缓存可重建，清理后相关工具可能重新下载依赖。",
                reclaimableRatio: 0.9
            )
        }

        if last == "node_modules" || last == ".next" || last == "dist" || last == "build" || last == "target" || lower.contains("/deriveddata/") {
            return ClassificationResult(
                category: .developerBuild,
                risk: .safeClean,
                recommendedAction: "项目可重建产物，确认项目不在运行后可清理",
                detail: "删除后可通过包管理器或构建命令重新生成。",
                reclaimableRatio: 0.95
            )
        }

        if lower.contains("/comfyui") ||
            lower.contains("/.ollama") ||
            lower.contains("/ollama-models") ||
            lower.contains("/ai-models") ||
            lower.contains("/huggingface") ||
            lower.contains("/modelscope") ||
            lower.contains("/models/") ||
            lower.hasSuffix("/models") {
            return ClassificationResult(
                category: .aiModel,
                risk: .review,
                recommendedAction: aiModelAction(for: lower),
                detail: "模型文件通常很大，但删除会影响对应工作流。",
                reclaimableRatio: 0.7
            )
        }

        if lower.contains("/library/containers/com.docker.docker") || lower.contains("/docker") {
            return ClassificationResult(
                category: .docker,
                risk: .review,
                recommendedAction: "用 Docker Desktop 或 docker system prune 清理",
                detail: "不要直接手删 Docker 容器目录。",
                reclaimableRatio: 0.5
            )
        }

        if lower.hasPrefix("/applications") || lower.hasSuffix(".app") {
            return ClassificationResult(
                category: .application,
                risk: .review,
                recommendedAction: "卸载不再使用的 App",
                detail: "优先通过 Finder 或应用卸载器移除。",
                reclaimableRatio: 0.8
            )
        }

        if lower.contains("/downloads") || lower.contains("/desktop") || lower.contains("/movies") {
            return ClassificationResult(
                category: .userData,
                risk: .review,
                recommendedAction: "人工确认后归档或删除",
                detail: "用户文件不应自动清理。",
                reclaimableRatio: 0.5
            )
        }

        return ClassificationResult(
            category: .unknown,
            risk: sizeBytes > 2_000_000_000 ? .review : .keep,
            recommendedAction: sizeBytes > 2_000_000_000 ? "大文件/目录，建议人工确认" : "保留",
            detail: sizeBytes > 2_000_000_000 ? "占用较大但规则无法判断用途。" : "体积较小或用途不明确。",
            reclaimableRatio: sizeBytes > 2_000_000_000 ? 0.3 : 0
        )
    }

    private static func safeCacheAction(for lowerPath: String) -> String {
        if lowerPath.contains("/.npm/_cacache") {
            return "可复制命令：npm cache clean --force"
        }
        if lowerPath.contains("/.cache/uv") {
            return "可复制命令：uv cache clean"
        }
        if lowerPath.contains("/pip") {
            return "可复制命令：pip cache purge"
        }
        if lowerPath.contains("homebrew") {
            return "可复制命令：brew cleanup -s"
        }
        return "可清理缓存；应用会在需要时重建"
    }

    private static func aiModelAction(for lowerPath: String) -> String {
        if lowerPath.contains("/.ollama") || lowerPath.contains("/ollama-models") {
            return "先运行 ollama list，再用 ollama rm 删除不用模型"
        }
        if lowerPath.contains("/comfyui") {
            return "按工作流确认不用的模型后手动移除"
        }
        return "确认模型来源和用途后再删除"
    }
}

private extension String {
    var standardizedPathForRules: String {
        NSString(string: self).standardizingPath
    }
}

private extension ItemKind {
    var isReadableKind: Bool {
        self != .inaccessible
    }
}
