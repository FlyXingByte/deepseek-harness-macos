<p align="center">
  <img src="https://raw.githubusercontent.com/FlyXingByte/deepseek-harness-macos/main/Assets/DeepSeekHarness.png" width="112" alt="DeepSeek Harness">
</p>

<h1 align="center">DeepSeek Harness v2.6.0</h1>

<p align="center"><strong>内核回退，一次退一步</strong></p>

<p align="center">
  <a href="https://github.com/FlyXingByte/deepseek-harness-macos/releases/download/v2.6.0/DeepSeek-Harness-v2.6.0-macOS-arm64.dmg"><strong>↓ 下载 DMG</strong></a>
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

以前回退只有一个目的地：随 App 内置的默认版本。连着更新过几次之后，一次回退会把中间那些能用的版本全部跳过。

现在改成按历史逐级回退：

- 🕘 **记住走过的路** —— 每次切换内核前，把你正在用的那一版记入历史，最多 10 条。
- 🎯 **写明退到哪** —— 菜单项从「恢复内置内核」变成 **回退到上一版内核 0.1.0-rc.6**，标题里直接写明目标版本。
- ↩️ **连点连退** —— 一路沿历史退回内置版本；没有可退目标时菜单置灰，不会再出现「点了等于没点」。
- 🛡️ **不会退坏** —— 回退目标按 SemVer 校验，且永不低于内置版本，启动器升级后也不会留下跑不起来的版本。

> [!NOTE]
> 版本历史从 v2.6.0 开始累积，更早构建的切换记录无法追溯。

### 🔒 安全边界没有变化

- 服务仍只监听 `127.0.0.1:3080`，不对局域网暴露。
- 不读取、迁移或修改 API Key、会话与工作区数据。
- 更新信息只来自固定的 npm 官方 dist-tags 地址，异常版本号会被拒绝。

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
shasum -a 256 -c DeepSeek-Harness-v2.6.0-macOS-arm64.dmg.sha256
```

---

<p align="center"><sub>非官方启动器 · 与 DeepSeek、Apple Inc. 无隶属、赞助或背书关系 · <a href="https://github.com/FlyXingByte/deepseek-harness-macos/blob/main/LICENSE">MIT</a> · <a href="https://github.com/FlyXingByte/deepseek-harness-macos/blob/main/NOTICE.md">NOTICE</a></sub></p>
