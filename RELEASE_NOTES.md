<p align="center">
  <img src="https://raw.githubusercontent.com/FlyXingByte/deepseek-harness-macos/main/Assets/DeepSeekHarness.png" width="112" alt="DeepSeek Harness">
</p>

<h1 align="center">DeepSeek Harness v3.0.0</h1>

<p align="center"><strong>官方 alpha.3，安全住进原生窗口</strong></p>

<p align="center">
  <a href="https://github.com/FlyXingByte/deepseek-harness-macos/releases/download/v3.0.0/DeepSeek-Harness-v3.0.0-macOS-arm64.dmg"><strong>↓ 下载 DMG</strong></a>
  ·
  <a href="https://github.com/FlyXingByte/deepseek-harness-macos/blob/main/INSTALL.md">安装说明</a>
  · <a href="https://github.com/FlyXingByte/deepseek-harness-macos/blob/main/CHANGELOG.md">更新历史</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-12%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 12+">
  <img src="https://img.shields.io/badge/Apple_Silicon-arm64-000000?style=flat-square" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/内核-dsh_0.1.2--alpha.3-4D6BFE?style=flat-square" alt="DSH 0.1.2-alpha.3">
  <img src="https://img.shields.io/badge/尚未公证-预发布-F59E0B?style=flat-square" alt="未公证">
</p>

---

### 这次解决了什么

`@deepseek-ai/dsh@0.1.2-alpha.3` 给本机 Web UI 增加了本次启动浏览器认证，并把 Session 投影缓存升级为逐会话文件。旧版启动器若只替换版本号，会遇到三个问题：裸地址返回 401、启动令牌落入日志、删除归档会话后留下新版缓存。

v3.0.0 以主版本升级补齐了整条兼容链：

- **安全认证**：严格识别本 App 启动进程输出的本机认证 URL，只在内存中交给 `WKWebView`，由 WebKit 完成 303 和 HttpOnly Cookie 交换。
- **日志脱敏**：所有写入 `harness-web.log` 的内容都会抹掉 `token=` 后的值；令牌不会进入弹窗、偏好设置或发布包。
- **401 不再误判**：外部 alpha 服务需要认证时，App 会明确提示先停止它，不会在同一个 3080 端口再启动第二个内核。
- **失败自动回退**：目标版本只有在本 App 启动、认证并完成最终 HTTP 200 页面载入后才成为 last-known-good；否则自动恢复 `0.1.1-rc.2`。
- **双更新通道**：普通用户继续使用 `latest/next`；只有显式启用 Alpha 实验通道后才跟进 npm `alpha`。
- **v4 缓存兼容**：归档清理同时处理旧 `session_projcache.json` 和新版 `session_projcache/sessions/<id>.json`。

### 安全边界

- 认证 URL 必须是精确的 `http://127.0.0.1:3080/`，且只有一个合法的 43 字符 token；任意外部地址或畸形值都会被拒绝。
- 归档清理只接受官方 Workspace v2、legacy projection cache v3 和直接位于 v4 records 目录中的普通 JSON 文件。
- 会话目录、项目目录和投影缓存文件只要是软链接或越过预期层级就会跳过。
- `workspace.json`、legacy cache 和本次目标的 v4 records 必须先成功备份；备份失败时不会移动或改写任何记录。
- API Key 仍由官方 Harness 管理。本次升级不读取、不复制、不迁移 `.credentials.yaml`。

### 兼容说明

- 默认推荐：`@deepseek-ai/dsh@0.1.2-alpha.3`
- 已验证回退：`@deepseek-ai/dsh@0.1.1-rc.2`
- 历史最低保留：`@deepseek-ai/dsh@0.1.0-rc.6`
- Node.js：`^22.19.0 || >=24.0.0`
- 默认 JSONL / Zstd Session 目录保持兼容。
- 官方 alpha.3 已移除可选 SQLite Session 后端；自定义 SQLite Profile 必须先用旧版导出。

### 首次打开

本版本为 ad-hoc 签名、**未经 Apple 公证**的公开预发布构建。请在访达中右键 App → **打开** → 再次确认；不要关闭 Gatekeeper。

---

<p align="center"><sub>非官方启动器 · 与 DeepSeek、Apple Inc. 无隶属、赞助或背书关系 · <a href="https://github.com/FlyXingByte/deepseek-harness-macos/blob/main/LICENSE">MIT</a> · <a href="https://github.com/FlyXingByte/deepseek-harness-macos/blob/main/NOTICE.md">NOTICE</a></sub></p>
