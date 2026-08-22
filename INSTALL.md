# 安装说明

1. 将“DeepSeek Harness.app”拖入旁边的 Applications 文件夹。
2. 需要 macOS 12+、Apple Silicon，以及 Node.js 22.19–22.x 或 24.0+（不支持 23.x）。
3. 本测试版尚未使用 Apple Developer ID 公证。首次启动请在访达中右键 App → 打开；不要关闭 Gatekeeper。
4. 首次启动会询问是否通过 npx 获取默认的官方 @deepseek-ai/dsh@0.1.0-rc.6。
5. 模型 API Key 请只在 Harness 的 Settings → Models 中配置。
6. 以后可从 App 菜单选择“检查并更新 Harness 内核…”。启动器只读取 npm 官方 dist-tag，发现更新后由你确认；每次切换前的版本都会记入历史，可通过“回退到上一版内核…”逐级回退。
7. 归档的会话仍会完整保存在磁盘上；需要真正删除时，从 App 菜单选择“清除已归档的会话…”，记录会移入废纸篓。

这是非官方启动器，与 DeepSeek 无隶属、赞助或官方背书关系。
