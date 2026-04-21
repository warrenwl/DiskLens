# DiskLens

DiskLens 是一个面向 AI/开发用户的 macOS 磁盘占用分析工具。MVP 只做只读扫描、全景展示、风险分级、清理建议和报告导出，不删除文件、不移动废纸篓、不执行清理命令。

## 运行

```bash
swift run DiskLens
```

如果要生成本地 `.app` bundle：

```bash
bash scripts/build_app_bundle.sh
open .build/release/DiskLens.app
```

## 第一版能力

- 默认扫描 `~`、`/Applications`、`/Library`、`/opt/homebrew`。
- 可选全 `/System/Volumes/Data` 或手动选择目录。
- 使用 treemap 展示磁盘占用全景，支持点击下钻、面包屑返回、hover/选中查看详情。
- 标记“可安全清理 / 谨慎清理 / 建议保留 / 系统相关”。
- 识别 ComfyUI、Ollama、HuggingFace/ModelScope、Docker、npm/uv/pip 缓存、node_modules、构建产物等常见大户。
- 扫描时显示当前路径、累计大小、文件/目录数量、耗时和不可读路径摘要。
- 表格支持搜索、风险筛选、大小阈值、排序、复制路径、Finder 中显示、复制建议命令。
- 导出 Markdown、JSON、SVG、PNG。

## 权限提示

DiskLens 不使用 root helper，也不会自动提权。如果某些目录无法读取，界面会列出不可读路径，并提供“完全磁盘访问”入口。给终端或 `.app` 授权后重新扫描即可看到更完整结果。

## 安全边界

当前版本仍然只读扫描：

- 不删除文件
- 不移动到废纸篓
- 不执行清理命令
- 只提供建议、报告和可复制命令

## 验证

```bash
swift run DiskLensChecks
swift build
```
