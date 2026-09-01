# 安装说明

1. 将“DeepSeek Harness.app”拖入旁边的 Applications 文件夹。
2. 需要 macOS 12+、Apple Silicon，以及 Node.js 22.19–22.x 或 24.0+（不支持 23.x）。
3. 本测试版尚未使用 Apple Developer ID 公证。首次启动请在访达中右键 App → 打开；不要关闭 Gatekeeper。
4. v3.0.0 首次启动会询问是否通过 npx 获取默认推荐的官方 @deepseek-ai/dsh@0.1.2-alpha.3；已验证回退点为 0.1.1-rc.2。
5. 模型 API Key 请只在 Harness 的 Settings → Models 中配置。
6. 更新菜单提供默认 `latest/next` 与显式 Alpha 实验通道。每次切换前的版本都会记入历史；新版未能完成本机认证和 HTTP 200 验证时会自动恢复上一个已知可用版本。
7. alpha.3 的本次启动浏览器令牌只在内存中使用并从日志脱敏；外部启动的鉴权服务需要先停止，再由 App 建立自己的安全会话。
8. 归档的会话仍会完整保存在磁盘上；需要真正删除时，从 App 菜单选择“清除已归档的会话…”。v3.0.0 同时兼容旧单文件和 alpha.3 逐会话投影缓存，记录会移入废纸篓，改写前必须成功备份。
9. alpha.3 已移除可选 SQLite Session 后端。默认 JSONL 用户不受影响；自定义 SQLite Profile 必须先在旧版导出。

这是非官方启动器，与 DeepSeek 无隶属、赞助或官方背书关系。
