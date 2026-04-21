from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from html import escape
from pathlib import Path
from textwrap import dedent


OUT_DIR = Path("/Users/warrn/study/AI Project")
SVG_PATH = OUT_DIR / "disk_usage_panorama.svg"
REPORT_PATH = OUT_DIR / "disk_usage_report.md"


def gib(kib: int) -> float:
    return kib / 1024 / 1024


@dataclass
class Node:
    name: str
    kib: int
    keep: str = "review"
    note: str = ""
    children: list["Node"] = field(default_factory=list)

    @property
    def gib(self) -> float:
        return gib(self.kib)


def n(name: str, kib: int, keep: str = "review", note: str = "", children=None) -> Node:
    return Node(name, kib, keep, note, children or [])


root = n(
    "Data 卷已用空间",
    414_366_137,
    "system",
    "du 扫描到的 /System/Volumes/Data 总量",
    [
        n(
            "/Users",
            365_347_168,
            "review",
            "你的个人数据几乎都在这里",
            [
                n(
                    "~/ComfyUI",
                    240_859_932,
                    "review",
                    "最大占用；主要是模型文件",
                    [
                        n("models/unet", 123_778_648, "review", "大模型主干，删不用的单个模型最有效"),
                        n("models/diffusion_models", 47_289_708, "review", "Flux/Z-Image 等 diffusion 模型"),
                        n("models/text_encoders", 32_721_400, "review", "文本编码器，部分可由多个工作流共用"),
                        n("models/checkpoints", 20_326_296, "review", "SD/写实/pony 等 checkpoint"),
                        n("models/loras", 6_429_904, "review", "LoRA 可按项目归档"),
                        n("models/vae", 3_940_512, "review", "VAE，通常体积较小"),
                        n("models/model_patches", 3_049_924, "review", "补丁/控制模型"),
                        n("ComfyUI .venv", 1_574_608, "clean", "虚拟环境可重建，但收益不大"),
                        n("ComfyUI output", 208_592, "clean", "生成图输出，可按需归档"),
                    ],
                ),
                n(
                    "~/Library",
                    40_239_284,
                    "review",
                    "应用数据、容器、缓存",
                    [
                        n("Containers", 22_691_344, "review", "应用沙盒数据，不建议整目录删除"),
                        n("Application Support", 10_023_488, "review", "Chrome/VS Code/Doubao 等数据"),
                        n("Caches", 6_280_200, "clean", "缓存可清，但会重建"),
                        n("Docker VM data", 9_404_732, "review", "建议用 Docker Desktop 清理，不要手删"),
                        n("QQ container", 4_128_976, "review", "聊天/缓存数据，先在应用内清理"),
                        n("Chrome support", 5_263_988, "review", "其中本地模型约 4.0G"),
                    ],
                ),
                n("~/.ollama", 15_744_296, "review", "Ollama 模型；用 ollama list/rm 管理"),
                n("~/.gemini", 13_395_368, "clean", "主要是 Antigravity/Gemini 浏览器录制"),
                n("~/project", 10_191_076, "review", "项目代码和构建产物"),
                n("~/ollama-models", 9_304_228, "review", "自定义 Ollama/模型目录"),
                n("~/.cache", 8_517_796, "clean", "uv/puppeteer/codex 等缓存"),
                n("~/ai-models", 5_790_988, "review", "HuggingFace/ModelScope 模型缓存"),
                n("~/.npm", 5_752_712, "clean", "npm cache，可重建"),
                n("~/study", 3_823_848, "review", "学习/项目文件"),
                n("其它用户文件", 12_928_641, "review", "下载、影片、Gradle/Rustup/VScode 等"),
            ],
        ),
        n("/Applications", 24_686_820, "review", "应用本体；卸载不用的 App 可回收"),
        n("/private", 12_089_364, "system", "系统缓存、vm、var/folders；不要整目录手删"),
        n("/Library", 5_584_844, "system", "系统级应用支持文件"),
        n("/System Data", 4_160_428, "system", "系统数据"),
        n("/opt/homebrew", 2_490_424, "clean", "brew cleanup 可清部分缓存/旧版本"),
        n("其它 Data 卷项目", 7_859, "system", "usr、MobileSoftwareUpdate 等很小"),
    ],
)

palette = {
    "clean": "#1f9d7a",
    "review": "#d88a21",
    "system": "#5b6472",
}

soft = {
    "clean": "#dff5ee",
    "review": "#fff0d7",
    "system": "#edf0f4",
}


def layout(nodes: list[Node], x: float, y: float, w: float, h: float, horizontal: bool = True):
    total = sum(node.kib for node in nodes)
    if total <= 0:
        return []
    out = []
    offset = 0.0
    for node in sorted(nodes, key=lambda item: item.kib, reverse=True):
        fraction = node.kib / total
        if horizontal:
            ww = w * fraction
            out.append((node, x + offset, y, ww, h))
            offset += ww
        else:
            hh = h * fraction
            out.append((node, x, y + offset, w, hh))
            offset += hh
    return out


def fit_text(text: str, w: float, size: int) -> str:
    # Conservative width estimate so labels stay inside narrow treemap cells.
    max_chars = max(int((w - 16) / (size * 0.62)), 0)
    if max_chars <= 3:
        return ""
    if len(text) <= max_chars:
        return text
    return text[: max_chars - 1] + "…"


def add_text(parts: list[str], x: float, y: float, text: str, size: int = 14, weight: int = 500, color: str = "#101418"):
    parts.append(
        f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" font-weight="{weight}" fill="{color}">{escape(text)}</text>'
    )


def rect(parts: list[str], x: float, y: float, w: float, h: float, fill: str, stroke: str = "#ffffff", sw: float = 1.5):
    parts.append(
        f'<rect x="{x:.1f}" y="{y:.1f}" width="{max(w, 0):.1f}" height="{max(h, 0):.1f}" rx="6" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'
    )


def draw_treemap(parts: list[str], node: Node, x: float, y: float, w: float, h: float, depth: int = 0):
    if not node.children or w < 60 or h < 38 or depth > 2:
        return
    horizontal = w >= h
    for child, cx, cy, cw, ch in layout(node.children, x, y, w, h, horizontal):
        fill = soft.get(child.keep, "#f6f6f6")
        stroke = palette.get(child.keep, "#777")
        rect(parts, cx, cy, cw, ch, fill, stroke, 1.2)
        if cw > 92 and ch > 42:
            label = fit_text(child.name, cw, 12)
            if label:
                add_text(parts, cx + 8, cy + 20, label, 12, 700)
            size_label = fit_text(f"{child.gib:.1f} GiB", cw, 12)
            if size_label:
                add_text(parts, cx + 8, cy + 38, size_label, 12, 500, "#323942")
            if child.note and cw > 190 and ch > 66:
                note = fit_text(child.note, cw, 10)
                if note:
                    add_text(parts, cx + 8, cy + 56, note, 10, 400, "#58606b")
        if depth < 2:
            pad = 7
            draw_treemap(parts, child, cx + pad, cy + 66, max(cw - pad * 2, 0), max(ch - 74, 0), depth + 1)


def legend(parts: list[str], x: float, y: float):
    items = [("可清理/可重建", "clean"), ("按需审查", "review"), ("系统/建议保留", "system")]
    for idx, (label, key) in enumerate(items):
        yy = y + idx * 26
        rect(parts, x, yy - 13, 18, 18, soft[key], palette[key], 1)
        add_text(parts, x + 28, yy + 1, label, 13, 500, "#27303a")


def make_svg():
    width, height = 1600, 1040
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="1600" height="1040" fill="#fbfaf7"/>',
        '<style>text{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB",Arial,sans-serif;letter-spacing:0}</style>',
    ]

    add_text(parts, 40, 58, "Mac 磁盘占用全景图", 30, 800)
    add_text(parts, 40, 88, "扫描对象：/System/Volumes/Data；当前 Data 卷约 395 GiB 已用，可用约 28 GiB", 15, 500, "#4c5663")
    add_text(parts, 40, 116, f"生成时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", 13, 400, "#68717d")
    legend(parts, 1260, 54)

    bar_x, bar_y, bar_w, bar_h = 40, 150, 1520, 38
    container_gib = 460.0
    data_used = 395.0
    system_used = 12.0
    free = 28.0
    other = max(container_gib - data_used - system_used - free, 0)
    segments = [
        ("Data 395 GiB", data_used, "#d88a21"),
        ("System 12 GiB", system_used, "#5b6472"),
        ("Free 28 GiB", free, "#1f9d7a"),
        ("APFS/保留/差异", other, "#c8cdd4"),
    ]
    pos = bar_x
    for label, val, color in segments:
        ww = bar_w * val / container_gib
        rect(parts, pos, bar_y, ww, bar_h, color, "#fbfaf7", 1)
        if ww > 110:
            add_text(parts, pos + 8, bar_y + 25, label, 13, 700, "#ffffff" if color != "#c8cdd4" else "#303842")
        pos += ww
    add_text(parts, 40, 218, "矩形面积越大，占用越大；绿色通常可重建，橙色需要人工确认，灰色建议保留或通过系统/应用工具清理。", 14, 500, "#3e4650")

    draw_treemap(parts, root, 40, 245, 1520, 735)
    add_text(parts, 40, 1016, "最主要结论：~/ComfyUI 约 229.7 GiB，占 Data 卷已用空间的 58%；清理模型比清理普通缓存更有效。", 15, 700, "#101418")
    parts.append("</svg>")
    SVG_PATH.write_text("\n".join(parts), encoding="utf-8")


def make_report():
    report = f"""# Mac 磁盘占用报告

生成时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

![磁盘占用全景图]({SVG_PATH})

## 总览

- APFS 容器约 460 GiB；`/System/Volumes/Data` 已用约 395 GiB，可用约 28 GiB。
- 用户目录 `/Users/warrn` 约 348.4 GiB，是主要来源。
- 最大单项是 `~/ComfyUI`，约 229.7 GiB，其中 `models` 约 227.8 GiB。
- 本地 Time Machine 快照未发现明显占用。

## 最大占用

| 位置 | 大小 | 判断 | 建议 |
| --- | ---: | --- | --- |
| `~/ComfyUI` | 229.7 GiB | 按需清理 | 删除不用的模型最有效，尤其 `models/unet`、`diffusion_models`、`text_encoders`、`checkpoints` |
| `~/Library` | 38.4 GiB | 谨慎 | 以应用内清理为主，不建议整目录删除 |
| `/Applications` | 23.5 GiB | 可审查 | 卸载不用的 App，比如大型创作/视频/开发 App |
| `~/.ollama` | 15.0 GiB | 按需清理 | 用 `ollama list` 和 `ollama rm` 删除不用模型 |
| `~/.gemini` | 12.8 GiB | 可清理 | `antigravity/browser_recordings` 约 11.9 GiB，若不需要录制可删 |
| `/private` | 11.5 GiB | 系统 | 不建议手删，重启可回收部分缓存 |
| `~/project` | 9.7 GiB | 可审查 | node_modules、.next、target、release 等可按项目重建 |
| `~/ollama-models` | 8.9 GiB | 按需清理 | 自定义模型目录，确认不用再删 |
| `~/.cache` | 8.1 GiB | 可清理 | 主要是 uv/puppeteer/codex 缓存，会自动重建 |
| `~/.npm` | 5.5 GiB | 可清理 | npm cache，可用 npm 命令清 |

## ComfyUI 大头

| 位置 | 大小 |
| --- | ---: |
| `~/ComfyUI/models/unet` | 118.0 GiB |
| `~/ComfyUI/models/diffusion_models` | 45.1 GiB |
| `~/ComfyUI/models/text_encoders` | 31.2 GiB |
| `~/ComfyUI/models/checkpoints` | 19.4 GiB |
| `~/ComfyUI/models/loras` | 6.1 GiB |

## 可优先清理

1. `~/.gemini/antigravity/browser_recordings`：约 11.9 GiB；如果不需要历史浏览器录制，优先级很高。
2. `~/.cache/uv`：约 6.8 GiB；Python/uv 包缓存，可重建。
3. `~/.npm/_cacache`：约 5.3 GiB；npm 包缓存，可重建。
4. `~/Library/Caches`：约 6.0 GiB；可清但会被应用重新生成。
5. Docker：`~/Library/Containers/com.docker.docker` 约 9.0 GiB；建议在 Docker Desktop 里 prune，不要直接删目录。
6. ComfyUI 模型：删 2-3 个不用的大模型就能回收几十 GiB。

## 建议保留或谨慎

- `~/Library/Containers/*`：里面可能是微信、QQ、Docker、抖音等应用数据，包含聊天记录、镜像、登录状态。
- `/private/var/folders`、`/private/var/vm`：系统缓存、swap/sleep 文件，别整目录删除。
- `~/ComfyUI/models/text_encoders`：有些文本编码器会被多个工作流共用，删除前确认工作流依赖。
- `~/ai-models`、`~/ollama-models`、`~/.ollama`：都是模型类文件，能清很多，但要按模型确认。

## 安全清理命令参考

先确认再执行；这些命令不会动系统目录，但会让以后需要时重新下载缓存：

```bash
npm cache clean --force
uv cache clean
pip cache purge
brew cleanup -s
```

Docker 建议用界面或：

```bash
docker system df
docker system prune
```

Ollama 建议先看清单：

```bash
ollama list
ollama rm <model-name>
```
"""
    REPORT_PATH.write_text(report, encoding="utf-8")


if __name__ == "__main__":
    make_svg()
    make_report()
    print(SVG_PATH)
    print(REPORT_PATH)
