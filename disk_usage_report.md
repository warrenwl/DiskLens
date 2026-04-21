# Mac 磁盘占用报告

生成时间：2026-04-20 17:14:43

![磁盘占用全景图](/Users/warrn/study/AI Project/disk_usage_panorama.svg)

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
