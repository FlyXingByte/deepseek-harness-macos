# 更新历史

本文件归档历史版本的发布说明。当前版本的发布说明见 [RELEASE_NOTES.md](./RELEASE_NOTES.md)，它同时作为 GitHub Release 页的正文。

---

## v3.0.0

主版本升级：完整支持官方 `@deepseek-ai/dsh@0.1.2-alpha.3`，并为本机浏览器认证、自动回退和新版数据布局建立新的兼容边界。

## 变更

- 新增默认 `latest/next` 与 Alpha 实验更新通道；实验版不再被默认通道静默选中。
- 默认推荐内核更新为 `0.1.2-alpha.3`，已验证回退点为 `0.1.1-rc.2`，历史最低仍保留到 `0.1.0-rc.6`。
- 捕获官方 `dsh web` 输出的本次启动认证 URL，让 `WKWebView` 完成 303 和 HttpOnly Cookie 交换。
- 新版未通过最终页面和 HTTP 200 验证时自动恢复上一个已知可用内核。
- 归档清理兼容 alpha.3 的 `storages/session_projcache/sessions/<id>.json` 逐会话缓存，同时继续修剪旧 `session_projcache.json`，避免旧记录再次 bootstrap。

## 安全与兼容

- 认证 URL 只接受精确的 `http://127.0.0.1:3080/`、单个 43 字符令牌；令牌只留在内存，所有日志写入统一脱敏。
- 裸根返回官方 401 时识别为“外部鉴权服务”，不再误启第二个进程；未知端口占用同样 fail closed。
- Workspace 必须是官方 v2、旧投影缓存必须是 v3；未知未来格式、软链接和不符合层级的路径均拒绝清理。
- 清理前必须成功备份 `workspace.json`、旧 cache 和本次目标的 v4 cache records；备份失败时零删除、零改写。
- 官方 alpha.3 已移除可选 SQLite Session 后端；默认 JSONL 不受影响，自定义 SQLite Profile 需在旧版导出。

---

## v2.7.0

归档之后，可以真正删除。

## 变更

- App 菜单新增「清除已归档的会话…（N 个）」，标题写明可清数量，没有归档会话时置灰。
- 确认框先给出会话数量与记录体积，确认后把会话记录移入废纸篓，可从废纸篓恢复。
- 同步清理 `workspace.json` 的归档集合与工作区成员列表，以及 `session_projcache.json` 的标题与统计缓存。
- 清除时先停止再重启由本 App 启动的 Harness 内核，因为内核会把会话列表常驻内存并回写。
- 改写列表文件前自动备份到 `~/Library/Logs/DeepSeek Harness/storage-backups/`，只保留最近 5 份。

## 安全与兼容

- 只删除 `<DSH_HOME>/sessions/<项目>/<会话>` 这一层，路径形状不符即跳过并报告。
- 目录未能移入废纸篓时保留其列表条目，避免产生看不见的孤儿记录。
- 子代理会话记录不参与清除：父子关系只存在于 zstd 压缩的日志头内。
- `DSH_HOME` 按官方 `dsh-home-paths` 规则解析，包含 `~` 展开与空值视为未设置。
- 外部启动的 `127.0.0.1:3080` 服务不会被擅自终止，只提示先行停止。

## v2.6.0

内核回退，一次退一步。

## 变更

- 「恢复内置内核」改为「回退到上一版内核」，菜单标题直接写明回退目标版本。
- 每次切换内核前记录当前版本，最多保留 10 条历史，可连续逐级回退直至内置版本。
- 没有可回退目标时菜单项置灰，不再提供空操作。
- 更新确认弹窗改为提示「可回退到你正要离开的这一版」，回退弹窗显示剩余可回退步数。

## 安全与兼容

- 服务仍只监听 `127.0.0.1:3080`，本次发布不对局域网暴露 Harness。
- 不迁移或复制模型凭据、Harness 会话、工作区，以及用户选定的官方内核版本。
- 回退目标按 SemVer 校验，且永不低于内置的 `@deepseek-ai/dsh@0.1.0-rc.6`，避免启动器升级后历史里残留无法运行的版本。
- 版本历史自本版本起累积，更早构建的切换记录无法追溯。

---

## v2.5.0

Native presentation and browser-launch fix release.

## Highlights

- Blends the standard macOS title bar into the Harness workspace and follows the page's light or dark appearance.
- Removes common browser tells from the embedded workspace: link previews, hand cursors, draggable page assets, whole-page rubber-band scrolling, WebKit-style context actions, and selectable navigation chrome.
- Keeps text editing native by preserving cut, copy, paste, undo, redo, delete, and select-all commands where they apply.

## Fixed

- Starts the official Harness Web UI with `--no-open`, so launching the native App no longer opens the same localhost workspace in Safari or another default browser.
- Keeps external HTTP and HTTPS links opening in the default browser while the local Harness workspace remains inside the App.

## Safety and compatibility

- The service remains bound to `127.0.0.1:3080`; this release does not expose Harness to the LAN.
- Model credentials, Harness sessions, workspaces, and the user-selected official core version are not migrated or copied by the launcher.
- The bundled rollback target remains the previously verified `@deepseek-ai/dsh@0.1.0-rc.6`.

## Distribution status

This build is distributed as an ad-hoc signed, non-notarized prerelease. On first launch, use Finder → right-click → Open; do not disable Gatekeeper.

---

## v2.4.0

Native Harness core update release.

## Why this matters

The native macOS launcher no longer has to be repackaged every time DeepSeek publishes a new Harness core. Users can keep the verified launcher window, explicitly check the official npm channel, and move to the newest valid release without manually editing commands. The update remains user-confirmed and reversible because upstream is still a developer preview.

## Added

- Added a native “Check and update Harness core” menu action backed only by the official npm dist-tags endpoint.
- Automatically selects the higher valid `latest` or `next` semantic version after user confirmation.
- Persists the selected official package version and uses it for subsequent npx launches.
- Added a native rollback action for the bundled verified `0.1.0-rc.6` version.

## Safety

- Rejects malformed package versions before constructing the npx package specifier.
- Restarts only a Harness process launched and owned by this App. An external service on port 3080 is never terminated automatically.
- Keeps updates user-initiated because upstream remains a developer preview with possible breaking changes.

---

## v2.3.1

Interaction fix release.

## Fixed

- Added persistent page/font zoom through the native View menu, plus Command-Plus, Command-Minus, and Command-0 shortcuts.
- Restored the standard macOS title bar so the window can be repositioned by dragging it with the mouse.
- Kept the embedded Harness content inside the standard content area so WebKit no longer captures title-bar drag gestures.

## Distribution status

This build is distributed as an ad-hoc signed, non-notarized prerelease. On first launch, use Finder → right-click → Open; do not disable Gatekeeper.

---

## v2.3

Initial public beta of the portable macOS launcher.

## Included

- Native WKWebView window tied to the whale Dock icon.
- Portable workspace selection with no machine-specific user paths.
- First-run confirmation before npx obtains the pinned official Harness package.
- Localhost-only Harness page loading and external-link handoff to the default browser.
- Drag-to-Applications DMG and SHA-256 checksum.

## Requirements

- macOS 12 or newer.
- Apple Silicon.
- Node.js 22.19+ or 24+ with npx.

## Important

This build is ad-hoc signed and not notarized because no Apple Developer ID certificate is available. It is published as a prerelease. On first launch, use Finder → right-click → Open. Do not disable Gatekeeper.

This is an unofficial launcher and is not affiliated with or endorsed by DeepSeek.
