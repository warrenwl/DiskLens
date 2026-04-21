import Foundation

public enum RecommendationEngine {
    public static func recommendations(from roots: [ScanItem]) -> [Recommendation] {
        let items = roots.flatMap { flatten($0) }
        var recommendations: [Recommendation] = []

        appendFirstMatch(
            in: items,
            matching: { $0.path.lowercased().contains("/.gemini/antigravity/browser_recordings") },
            title: "清理 Gemini/Antigravity 浏览器录制",
            command: nil,
            steps: "确认不需要历史浏览器录制后，手动删除该目录下的旧录制文件。",
            rationale: "路径命中浏览器录制目录，通常属于可回看的临时调试/操作记录，不影响系统运行。",
            to: &recommendations
        )

        appendFirstMatch(
            in: items,
            matching: { $0.path.lowercased().contains("/.cache/uv") },
            title: "清理 uv 包缓存",
            command: "uv cache clean",
            steps: "这是可重建依赖缓存，清理后需要时会重新下载。",
            rationale: "路径命中 uv cache，属于包下载/构建缓存，可由 uv 重新生成。",
            to: &recommendations
        )

        appendFirstMatch(
            in: items,
            matching: { $0.path.lowercased().contains("/.npm/_cacache") },
            title: "清理 npm 包缓存",
            command: "npm cache clean --force",
            steps: "这是 npm 下载缓存，项目依赖本身不会因此被删除。",
            rationale: "路径命中 npm _cacache，属于 npm 下载缓存，不是项目源代码。",
            to: &recommendations
        )

        appendFirstMatch(
            in: items,
            matching: { $0.path.lowercased().contains("/library/caches/homebrew") || $0.path.lowercased().contains("/opt/homebrew") },
            title: "清理 Homebrew 旧缓存",
            command: "brew cleanup -s",
            steps: "清理 Homebrew 旧版本和下载缓存，保留当前安装版本。",
            rationale: "路径命中 Homebrew 安装/缓存区域，适合用 brew 自带 cleanup 做保守清理。",
            to: &recommendations
        )

        appendFirstMatch(
            in: items,
            matching: { $0.path.lowercased().contains("/library/containers/com.docker.docker") },
            title: "审查 Docker 镜像与卷",
            command: "docker system df",
            steps: "先查看 Docker 空间构成，再用 Docker Desktop 或 docker system prune 清理。",
            rationale: "Docker 数据目录可能包含镜像、容器、卷和 build cache，直接删除风险高，应先用 Docker 工具审查。",
            to: &recommendations
        )

        appendFirstMatch(
            in: items,
            matching: { $0.path.lowercased().contains("/.ollama") || $0.path.lowercased().contains("/ollama-models") },
            title: "审查 Ollama 模型",
            command: "ollama list",
            steps: "先列出模型，再用 ollama rm <model-name> 删除不用模型。",
            rationale: "路径命中 Ollama 模型存储，模型文件很大但删除会影响本地模型调用。",
            to: &recommendations
        )

        let comfyCandidates = items.filter {
            $0.path.lowercased().contains("/comfyui/models") && $0.sizeBytes > 1_000_000_000
        }
        if let largest = comfyCandidates.max(by: { $0.sizeBytes < $1.sizeBytes }) {
            recommendations.append(
                Recommendation(
                    title: "审查 ComfyUI 大模型",
                    affectedPath: largest.path,
                    estimatedBytes: largest.reclaimableBytes,
                    risk: .review,
                    command: nil,
                    steps: "按工作流确认不用的 checkpoint、unet、diffusion model、text encoder 后手动移除。",
                    rationale: "路径命中 ComfyUI models 且体积超过 1GB，是最可能回收大量空间的 AI 模型资产。"
                )
            )
        }

        let buildItems = items
            .filter { $0.category == .developerBuild && $0.sizeBytes > 300_000_000 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(5)
        for item in buildItems {
            recommendations.append(
                Recommendation(
                    title: "清理可重建构建产物",
                    affectedPath: item.path,
                    estimatedBytes: item.reclaimableBytes,
                    risk: .safeClean,
                    command: nil,
                    steps: "确认对应项目未运行后删除；需要时可重新安装依赖或重新构建。",
                    rationale: "目录类型被识别为 node_modules、.next、target、build 或 dist，可由项目工具链重建。"
                )
            )
        }

        return recommendations
            .sorted { lhs, rhs in
                if lhs.risk.sortOrder == rhs.risk.sortOrder {
                    return lhs.estimatedBytes > rhs.estimatedBytes
                }
                return lhs.risk.sortOrder < rhs.risk.sortOrder
            }
    }

    public static func flatten(_ item: ScanItem) -> [ScanItem] {
        [item] + item.children.flatMap { flatten($0) }
    }

    public static func relevantRecommendations(
        _ recommendations: [Recommendation],
        selectedPath: String?
    ) -> [Recommendation] {
        guard let selectedPath else { return recommendations }
        return recommendations.filter { recommendation in
            recommendation.affectedPath == selectedPath ||
                recommendation.affectedPath.hasPrefix(selectedPath + "/") ||
                selectedPath.hasPrefix(recommendation.affectedPath + "/")
        }
    }

    private static func appendFirstMatch(
        in items: [ScanItem],
        matching predicate: (ScanItem) -> Bool,
        title: String,
        command: String?,
        steps: String,
        rationale: String,
        to recommendations: inout [Recommendation]
    ) {
        guard let item = items.filter(predicate).max(by: { $0.sizeBytes < $1.sizeBytes }) else {
            return
        }
        recommendations.append(
            Recommendation(
                title: title,
                affectedPath: item.path,
                estimatedBytes: item.reclaimableBytes,
                risk: item.risk,
                command: command,
                steps: steps,
                rationale: rationale
            )
        )
    }
}
