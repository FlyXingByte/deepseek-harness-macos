<h1 align="center">DeepSeek Harness for macOS</h1>

<p align="center"><strong>让官方 DeepSeek Harness，真正住进程序坞。</strong></p>
<p align="center">非官方启动器 · 独立窗口 · 本机工作区</p>

<p align="center">
  <a href="https://github.com/FlyXingByte/deepseek-harness-macos/releases/download/v2.3/DeepSeek-Harness-v2.3-macOS-arm64.dmg"><strong>↓ 下载 v2.3</strong></a>
</p>
<p align="center">
  <a href="./INSTALL.md">安装说明</a>
  · <a href="https://github.com/deepseek-ai/deepseek-harness">官方 Harness ↗</a>
</p>

<p align="center">Apple Silicon · macOS 12+ · Node.js 22.19–22.x 或 24.0+（不支持 23.x）</p>

> [!WARNING]
> **v2.3 尚未公证。** 首次打开：在访达中右键 App → **打开** → 再确认；不要关闭 Gatekeeper。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./Assets/DeepSeekHarnessHeroDark.png">
    <source media="(prefers-color-scheme: light)" srcset="./Assets/DeepSeekHarnessHeroLight.png">
    <img src="./Assets/DeepSeekHarnessHeroLight.png" width="1200" alt="蓝色胖鲸应用图标的产品主视觉">
  </picture>
</p>

## 一个窗口。不是一个浏览器标签。

这是一个轻量的原生 macOS 启动器。它负责启动固定版本的官方 DeepSeek Harness Web UI，并把工作台显示在独立窗口中。

- **从程序坞打开**：独立窗口、菜单栏和 App 图标。
- **服务留在本机**：Harness Web UI 仅监听 `127.0.0.1:3080`。
- **工作区由你选择**：使用隔离的默认目录，或切换到自己的项目文件夹。

## 三步安装

1. [下载 v2.3 DMG](https://github.com/FlyXingByte/deepseek-harness-macos/releases/download/v2.3/DeepSeek-Harness-v2.3-macOS-arm64.dmg)，打开后把 **DeepSeek Harness.app** 拖入 **Applications**。
2. 在“应用程序”中右键 App，选择 **打开**，然后在 macOS 提示中再次确认。
3. 首次启动时确认通过 `npx` 获取固定版本的官方 `@deepseek-ai/dsh@0.1.0-rc.6`，等待工作台出现。

首次获取需要联网。请先从 [Node.js 官网](https://nodejs.org/en/download) 安装 Node.js；Harness 与 Node.js 均不包含在 DMG 中。

## 第一次使用

1. 打开右上角 **Settings → Models**，配置 Provider 与 API Key。
2. 保存设置，并在模型选择器中选中刚配置的模型。
3. 点击 **Choose workspace**，选择一个独立的项目文件夹。
4. 新建会话，选择合适的权限，再输入任务。

[查看官方 Web UI 快速指南 ↗](https://deepseek-harness.github.io/deepseek-harness/guide/quickstart)

<details>
<summary><strong>开始第一个任务与权限建议</strong></summary>

建议先用 **Read Only** 做一个小任务：

```text
只读分析这个项目。告诉我它解决什么问题、主要文件在哪里，以及下一步最值得做的三件事。不要修改文件。
```

- **Read Only**：阅读、总结、审查，不修改文件。
- **Workspace Write**：普通开发、修改文件和运行项目内命令。
- **Full access**：仅在明确需要超出工作区时使用，并逐项确认风险。

</details>

## 边界很清楚

- **Launcher**：本仓库提供，包含在 DMG 中，负责窗口、程序坞图标和启动管理。
- **DeepSeek Harness**：由 DeepSeek 官方维护，不包含在 DMG 中；首次启动经你确认后获取。
- **Node.js**：由用户安装，用于运行 `npx` 与 Harness。

> [!NOTE]
> DeepSeek Harness 仍处于 **Developer Preview**，可能出现破坏兼容性的变化。本启动器明确请求顶层包 `@deepseek-ai/dsh@0.1.0-rc.6`；其依赖由 npm 按官方包声明解析。

这是 FlyX 独立制作的非官方启动器，与 DeepSeek 或 Apple Inc. 无隶属、赞助或背书关系。名称仅用于说明兼容性；鲸鱼图标与主视觉不是官方素材。

## 工作区与数据

- 默认工作区为 `~/Documents/DeepSeek Harness Workspace`；也可从 App 菜单切换。
- 模型凭据由官方 Harness 管理；启动器自身不存储或迁移 API Key。
- Web UI 只监听本机，但模型请求仍会发送给你配置的 Provider。
- 外接盘建议使用 APFS；exFAT 可能因受保护写入能力不足出现 `ENOTSUP`。
- 启动日志位于 `~/Library/Logs/DeepSeek Harness/harness-web.log`。

<details>
<summary><strong>安全细节与官方参考</strong></summary>

外部 HTTP/HTTPS 链接交给默认浏览器；未知自定义协议会被阻止。插件、MCP 和其他第三方组件可能执行外部代码，安装前请单独审查来源与权限。Harness 通过 Models 页面保存的 Key 位于 `$DSH_HOME/.credentials.yaml`，页面不会回显明文。

[权限预设](https://deepseek-harness.github.io/deepseek-harness/reference/subsystems/permission-presets) · [沙箱边界](https://deepseek-harness.github.io/deepseek-harness/reference/subsystems/sandbox) · [操作审批](https://deepseek-harness.github.io/deepseek-harness/reference/subsystems/approval) · [凭据管理](https://deepseek-harness.github.io/deepseek-harness/reference/subsystems/credentials) · [本地 Web Server](https://deepseek-harness.github.io/deepseek-harness/reference/subsystems/web-server) · [会话遥测](https://deepseek-harness.github.io/deepseek-harness/reference/subsystems/session-telemetry)

</details>

<details>
<summary><strong>更多 DeepSeek Harness 官方资料</strong></summary>

- [DeepSeek Harness 官方页面](https://deepseek.com/harness/)
- [官方 GitHub 仓库](https://github.com/deepseek-ai/deepseek-harness)
- [中文快速启动](https://github.com/deepseek-ai/deepseek-harness/blob/master/README.zh.md)
- [官方文档主页](https://deepseek-harness.github.io/deepseek-harness/)
- [模型与 Provider 配置](https://deepseek-harness.github.io/deepseek-harness/guide/providers)
- [权限预设说明](https://deepseek-harness.github.io/deepseek-harness/reference/subsystems/permission-presets)
- [CLI 模式说明（中文）](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/cli/README.zh.md)
- [CLI 精确行为参考（中文）](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/cli/reference/README.zh.md)

</details>

<details>
<summary><strong>常见问题</strong></summary>

**macOS 提示无法验证开发者？** 这是未公证的公开测试版。请在访达中右键 App → **打开** → 再确认；不要关闭 Gatekeeper。

**提示找不到 Node.js 或 npx？** 从 [Node.js 官网](https://nodejs.org/en/download) 安装 Node.js 22.19–22.x 或 24.0+（不支持 23.x），然后重新打开 App。

**输入框不可用？** 先在 **Settings → Models** 配置并选择模型，再点击 **Choose workspace** 选择工作区。

</details>

<details>
<summary><strong>验证下载文件与本地构建</strong></summary>

下载 [SHA-256 文件](https://github.com/FlyXingByte/deepseek-harness-macos/releases/download/v2.3/DeepSeek-Harness-v2.3-macOS-arm64.dmg.sha256) 后，在终端运行：

```sh
cd ~/Downloads
shasum -a 256 -c DeepSeek-Harness-v2.3-macOS-arm64.dmg.sha256
```

本地构建与验证：

```sh
./scripts/build.sh
./scripts/create-dmg.sh
./scripts/verify-release.sh
```

脚本只进行 ad-hoc hardened runtime 签名；无警告分发仍需要 Developer ID Application 证书和 Apple notarization。

</details>

---

<p align="center"><sub><a href="https://github.com/FlyXingByte/deepseek-harness-macos/releases/tag/v2.3">v2.3</a> · DSH 0.1.0-rc.6 · arm64 · <a href="./LICENSE">MIT</a> · <a href="./NOTICE.md">NOTICE</a> · <a href="https://github.com/FlyXingByte/deepseek-harness-macos/issues">Issues</a></sub></p>
