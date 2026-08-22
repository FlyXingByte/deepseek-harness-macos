<p align="center">
  <img src="https://raw.githubusercontent.com/FlyXingByte/deepseek-harness-macos/main/Assets/DeepSeekHarness.png" width="112" alt="DeepSeek Harness">
</p>

<h1 align="center">DeepSeek Harness v2.7.0</h1>

<p align="center"><strong>归档之后，可以真正删除</strong></p>

<p align="center">
  <a href="https://github.com/FlyXingByte/deepseek-harness-macos/releases/download/v2.7.0/DeepSeek-Harness-v2.7.0-macOS-arm64.dmg"><strong>↓ 下载 DMG</strong></a>
  · <a href="https://github.com/FlyXingByte/deepseek-harness-macos/blob/main/INSTALL.md">安装说明</a>
  · <a href="https://github.com/FlyXingByte/deepseek-harness-macos/blob/main/CHANGELOG.md">更新历史</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-12%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 12+">
  <img src="https://img.shields.io/badge/Apple_Silicon-arm64-000000?style=flat-square" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/内核-dsh_0.1.0--rc.6-4D6BFE?style=flat-square" alt="DSH 0.1.0-rc.6">
  <img src="https://img.shields.io/badge/尚未公证-预发布-F59E0B?style=flat-square" alt="未公证">
</p>

---

### ✨ 这次更新了什么

官方内核只提供归档：会话从侧边栏消失，完整记录仍然留在 `~/.dsh/sessions` 里，一个字节都没少。v2.7.0 让启动器接手最后一步。

- 🗑️ **一键清除** —— App 菜单新增 **清除已归档的会话…（N 个）**，标题里直接写明有多少个可清；没有归档会话时置灰。
- 🧾 **先算再问** —— 确认框写明这次会清掉几个会话、多少体积，确认之后才动手。
- ♻️ **进废纸篓，不是凭空消失** —— 会话记录移入废纸篓，误清可以直接拖回来。
- 🧹 **列表一起清干净** —— 同时清理 `workspace.json` 的归档集合与工作区成员，以及 `session_projcache.json` 里的标题和统计缓存，侧边栏不留残影。
- 🛟 **改写前自动备份** —— 两个列表文件在改写前备份到 `~/Library/Logs/DeepSeek Harness/storage-backups/`，只保留最近 5 份。

> [!NOTE]
> 内核会把会话列表常驻内存并回写，所以清除时会先停止再重启 Harness 内核，工作台里未发送的内容可能丢失。如果 `127.0.0.1:3080` 是你在终端里启动的服务，启动器只提示你先停掉它，不会擅自终止外部进程。

### 🔒 安全边界

- 只删除 `<DSH_HOME>/sessions/<项目>/<会话>` 这一层，路径形状不符即跳过并报告，不会波及其他目录。
- 某个目录没能移入废纸篓时，它的列表条目会被保留，不会产生看不见的孤儿记录。
- 子代理会话记录不会被连带删除：父子关系只存在于 zstd 压缩的日志头内，启动器不做猜测。
- `DSH_HOME` 按官方规则解析（含 `~` 展开、空值视为未设置），不写死 `~/.dsh`。
- 服务仍只监听 `127.0.0.1:3080`；不读取、迁移或修改 API Key 与工作区数据。

### 📦 环境要求

| 项目 | 要求 |
| :--- | :--- |
| 系统 | macOS 12 或更高 |
| 芯片 | Apple Silicon |
| Node.js | 22.19–22.x 或 24.0+（不支持 23.x） |
| Harness 内核 | `@deepseek-ai/dsh@0.1.0-rc.6`，首次启动经你确认后通过 `npx` 获取 |

### ⚠️ 首次打开

本版本为 ad-hoc 签名、**未经 Apple 公证**的预发布版。请在访达中右键 App → **打开** → 再次确认；不要关闭 Gatekeeper。

### 🔐 校验下载

```sh
cd ~/Downloads
shasum -a 256 -c DeepSeek-Harness-v2.7.0-macOS-arm64.dmg.sha256
```

---

<p align="center"><sub>非官方启动器 · 与 DeepSeek、Apple Inc. 无隶属、赞助或背书关系 · <a href="https://github.com/FlyXingByte/deepseek-harness-macos/blob/main/LICENSE">MIT</a> · <a href="https://github.com/FlyXingByte/deepseek-harness-macos/blob/main/NOTICE.md">NOTICE</a></sub></p>
