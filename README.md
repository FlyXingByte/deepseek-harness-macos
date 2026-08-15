# DeepSeek Harness for macOS (Unofficial)

一个独立制作的原生 macOS 启动器：负责启动官方 DeepSeek Harness，并把本机 Web UI 放进独立的 WKWebView 窗口中。

> 这是非官方项目，与 DeepSeek 无隶属、赞助或官方背书关系。“DeepSeek / DeepSeek Harness”仅用于说明兼容对象。胖鲸图标为原创，并非 DeepSeek 官方 Logo。

## 功能

- 原生 macOS 窗口和程序坞图标，不再跳到普通浏览器标签页。
- 只连接本机 http://127.0.0.1:3080。
- 首次启动前明确询问是否通过 npx 获取官方 Harness 软件包。
- 默认工作区为“文稿/DeepSeek Harness Workspace”，也可从 App 菜单选择其他文件夹。
- 外部 HTTP/HTTPS 链接交给默认浏览器；阻止未知自定义协议。
- 启动器自身不存储、迁移或主动上传 API Key；模型凭据由官方 Harness 管理。

## 系统要求

- macOS 12 或更高版本。
- Apple Silicon Mac。
- Node.js 22.19+ 或 24+，并且系统中可找到 npx。
- 首次获取官方 Harness 时需要网络。

官方 Harness 当前仍是 Developer Preview，未来可能发生不兼容变化。

## 安装

1. 从 GitHub Releases 下载 DeepSeek-Harness-v2.3-macOS-arm64.dmg。
2. 打开 DMG，把 DeepSeek Harness 拖入 Applications。
3. 当前测试版没有 Apple Developer ID 公证。首次打开时请在访达中右键 App，选择“打开”，再确认一次；不要关闭 Gatekeeper。
4. 首次启动会询问是否通过 npx 获取 @deepseek-ai/dsh@0.1.0-rc.6。
5. 在 Harness 的 Settings → Models 中自行配置模型凭据。

## 工作区

默认目录：

    ~/Documents/DeepSeek Harness Workspace

可在 App 菜单中选择“选择 Harness 工作区…”。如果 Harness 服务已经运行，重启服务后新工作区才会生效。

外接硬盘建议使用 APFS。exFAT 不支持 Harness 某些受保护的新文件写入语义，可能出现 ENOTSUP。

## 本地构建

    ./scripts/build.sh
    ./scripts/create-dmg.sh
    ./scripts/verify-release.sh

构建产物位于 dist/。构建脚本仅做 ad-hoc hardened runtime 签名；公开的无警告分发仍需要 Developer ID Application 证书和 Apple notarization。

## 安全与隐私

- 启动器调用固定版本的官方 npm 包：@deepseek-ai/dsh@0.1.0-rc.6。
- API Key 由官方 Harness 的 Settings → Models 管理，本仓库不存储凭据。
- 日志只写入当前用户的 ~/Library/Logs/DeepSeek Harness/harness-web.log。
- App 不包含 Node、Harness、用户工作区、.dsh、.env、会话或日志。
- 安装插件、MCP 或其他第三方组件会执行外部代码，请单独审查和授权。

## 版本

- macOS 启动器：2.3（Build 7）
- 默认 Harness 包：0.1.0-rc.6
- 架构：arm64

## 上游与许可证

- 官方项目：https://github.com/deepseek-ai/deepseek-harness
- 官方运行方式：https://github.com/deepseek-ai/deepseek-harness#run
- 本启动器采用 MIT License。
- DeepSeek Harness 是独立的上游项目，Copyright (c) 2026 DeepSeek，并按其 MIT License 提供。
