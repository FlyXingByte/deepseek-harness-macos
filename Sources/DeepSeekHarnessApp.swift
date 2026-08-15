import AppKit
import Foundation
import WebKit

private let appDisplayName = "DeepSeek Harness"
private let harnessURL = URL(string: "http://127.0.0.1:3080/")!
private let harnessPackageVersion = "0.1.0-rc.6"
private let harnessPackageSpecifier = "@deepseek-ai/dsh@\(harnessPackageVersion)"
private let harnessProjectURL = URL(string: "https://github.com/deepseek-ai/deepseek-harness")!
private let maximumProbeAttempts = 180

private struct NodeRuntime {
    let nodeURL: URL
    let npxURL: URL
    let version: String
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var startupView: NSView!
    private var statusLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!
    private var retryButton: NSButton!
    private var logButton: NSButton!

    private var probeTimer: Timer?
    private var probeAttempts = 0
    private var probeInFlight = false
    private var harnessProcess: Process?
    private var harnessLogHandle: FileHandle?
    private var harnessWasStartedByThisApp = false
    private var isTerminating = false
    private var harnessPageHasLoaded = false
    private let workspaceDefaultsKey = "HarnessWorkspacePath"
    private let packageApprovalDefaultsKey = "ApprovedOfficialHarnessPackageDownload"
    private lazy var workspaceURL: URL = resolveWorkspaceURL()

    private lazy var probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 2.0
        configuration.connectionProxyDictionary = [:]
        configuration.httpAdditionalHeaders = [
            "Cache-Control": "no-cache, no-store, max-age=0",
            "Pragma": "no-cache"
        ]
        return URLSession(configuration: configuration)
    }()

    private lazy var logURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("DeepSeek Harness", isDirectory: true)
            .appendingPathComponent("harness-web.log", isDirectory: false)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureApplicationIcon()
        buildMainMenu()
        buildWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        connectToOrStartHarness()
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        probeTimer?.invalidate()
        probeTimer = nil
        probeSession.invalidateAndCancel()

        if harnessWasStartedByThisApp, let process = harnessProcess, process.isRunning {
            appendLog("Stopping Harness because the native app is quitting.\n")
            process.terminate()
        }

        try? harnessLogHandle?.synchronize()
        try? harnessLogHandle?.close()
        harnessLogHandle = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func configureApplicationIcon() {
        if let iconPath = Bundle.main.path(forResource: "DeepSeekHarness", ofType: "png"),
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = icon
        }
    }

    private func buildWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 1320, height: 860)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = appDisplayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 900, height: 600)
        window.center()
        window.setFrameAutosaveName("DeepSeekHarnessMainWindow")
        window.tabbingMode = .disallowed
        window.delegate = self

        let rootView = NSView(frame: contentRect)
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(calibratedRed: 0.018, green: 0.043, blue: 0.115, alpha: 1).cgColor
        window.contentView = rootView

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        webView.isHidden = true
        rootView.addSubview(webView)

        startupView = makeStartupView()
        startupView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(startupView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: rootView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            startupView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            startupView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            startupView.topAnchor.constraint(equalTo: rootView.topAnchor),
            startupView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    private func makeStartupView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.018, green: 0.043, blue: 0.115, alpha: 1).cgColor

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown

        statusLabel = NSTextField(labelWithString: "正在启动 DeepSeek Harness")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 25, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.alignment = .center

        detailLabel = NSTextField(labelWithString: "正在连接本机服务…")
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.68)
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 3
        detailLabel.lineBreakMode = .byWordWrapping

        progressIndicator = NSProgressIndicator()
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.startAnimation(nil)

        retryButton = NSButton(title: "重新尝试", target: self, action: #selector(retryConnection(_:)))
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.bezelStyle = .rounded
        retryButton.isHidden = true

        logButton = NSButton(title: "查看日志", target: self, action: #selector(showLog(_:)))
        logButton.translatesAutoresizingMaskIntoConstraints = false
        logButton.bezelStyle = .rounded
        logButton.isHidden = true

        let buttonStack = NSStackView(views: [retryButton, logButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 12

        let stack = NSStackView(views: [iconView, statusLabel, detailLabel, progressIndicator, buttonStack])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.setCustomSpacing(24, after: iconView)
        stack.setCustomSpacing(8, after: statusLabel)
        stack.setCustomSpacing(24, after: detailLabel)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 132),
            iconView.heightAnchor.constraint(equalToConstant: 132),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            buttonStack.widthAnchor.constraint(equalToConstant: 250),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -10)
        ])

        return view
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu(title: "MainMenu")

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: appDisplayName)
        let aboutItem = NSMenuItem(title: "关于 \(appDisplayName)", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        let chooseWorkspaceItem = NSMenuItem(title: "选择 Harness 工作区…", action: #selector(chooseWorkspace(_:)), keyEquivalent: "")
        chooseWorkspaceItem.target = self
        appMenu.addItem(chooseWorkspaceItem)
        let revealWorkspaceItem = NSMenuItem(title: "在访达中显示工作区", action: #selector(revealWorkspace(_:)), keyEquivalent: "")
        revealWorkspaceItem.target = self
        appMenu.addItem(revealWorkspaceItem)
        let projectItem = NSMenuItem(title: "打开 Harness 官方项目", action: #selector(openHarnessProject(_:)), keyEquivalent: "")
        projectItem.target = self
        appMenu.addItem(projectItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏 \(appDisplayName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "隐藏其他应用", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 \(appDisplayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "显示")
        let reloadItem = NSMenuItem(title: "重新载入", action: #selector(reloadPage(_:)), keyEquivalent: "r")
        reloadItem.target = self
        viewMenu.addItem(reloadItem)
        let actualSizeItem = NSMenuItem(title: "实际大小", action: #selector(resetMagnification(_:)), keyEquivalent: "0")
        actualSizeItem.target = self
        viewMenu.addItem(actualSizeItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appDisplayName,
            .applicationVersion: version,
            .version: "非官方原生窗口版 · Harness \(harnessPackageVersion)",
            .credits: NSAttributedString(
                string: "独立制作的非官方 macOS 启动器，与 DeepSeek 无隶属、赞助或官方背书关系。\n仅连接本机 127.0.0.1:3080；图标为原创，并非 DeepSeek 官方 Logo。"
            )
        ])
    }

    @objc private func chooseWorkspace(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "选择 DeepSeek Harness 工作区"
        panel.message = "Harness 将以这个文件夹作为默认工作区。已运行的服务需要重启后才会切换。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = workspaceURL
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let selectedURL = panel.url else { return }
            self.workspaceURL = selectedURL.standardizedFileURL
            UserDefaults.standard.set(self.workspaceURL.path, forKey: self.workspaceDefaultsKey)

            let alert = NSAlert()
            alert.messageText = "工作区已保存"
            alert.informativeText = "下次启动 Harness 服务时将使用：\n\(self.workspaceURL.path)"
            alert.addButton(withTitle: "好")
            alert.beginSheetModal(for: self.window)
        }
    }

    @objc private func revealWorkspace(_ sender: Any?) {
        do {
            try ensureWorkspaceExists()
            NSWorkspace.shared.open(workspaceURL)
        } catch {
            showStartup(status: "无法打开工作区", detail: error.localizedDescription, isError: true)
        }
    }

    @objc private func openHarnessProject(_ sender: Any?) {
        NSWorkspace.shared.open(harnessProjectURL)
    }

    @objc private func reloadPage(_ sender: Any?) {
        if harnessPageHasLoaded {
            webView.reload()
        } else {
            retryConnection(sender)
        }
    }

    @objc private func resetMagnification(_ sender: Any?) {
        webView.setMagnification(1.0, centeredAt: NSPoint(x: webView.bounds.midX, y: webView.bounds.midY))
    }

    @objc private func retryConnection(_ sender: Any?) {
        probeTimer?.invalidate()
        probeTimer = nil
        probeAttempts = 0
        probeInFlight = false
        harnessPageHasLoaded = false
        showStartup(status: "正在连接 DeepSeek Harness", detail: "正在检查本机服务…", isError: false)
        connectToOrStartHarness()
    }

    @objc private func showLog(_ sender: Any?) {
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
        } else {
            NSWorkspace.shared.open(logURL.deletingLastPathComponent())
        }
    }

    private func connectToOrStartHarness() {
        probeHarness { [weak self] isReady in
            guard let self else { return }
            if isReady {
                self.loadHarnessPage()
            } else if let process = self.harnessProcess, process.isRunning {
                self.showStartup(status: "正在启动 DeepSeek Harness", detail: "本机服务正在初始化…", isError: false)
                self.beginProbeLoop()
            } else {
                self.startHarnessProcess()
            }
        }
    }

    private func startHarnessProcess() {
        let discovery = discoverNodeRuntime()
        guard let runtime = discovery.runtime else {
            showStartup(
                status: "需要兼容的 Node.js",
                detail: discovery.detail,
                isError: true
            )
            return
        }

        guard confirmOfficialPackageDownloadIfNeeded() else {
            showStartup(
                status: "尚未启动 Harness",
                detail: "首次启动需要你确认通过 npx 获取官方 \(harnessPackageSpecifier) 软件包。",
                isError: true
            )
            return
        }

        do {
            try ensureWorkspaceExists()
            try prepareLogFile()
            appendLog("\n--- Native app launch \(ISO8601DateFormatter().string(from: Date())) ---\n")
            appendLog("Harness package: \(harnessPackageSpecifier)\n")
            appendLog("Node: \(runtime.version) at \(runtime.nodeURL.path)\n")
            appendLog("Workspace: \(workspaceURL.path)\n")

            let process = Process()
            process.executableURL = runtime.npxURL
            process.arguments = ["--yes", harnessPackageSpecifier, "web"]
            process.currentDirectoryURL = workspaceURL
            var environment = ProcessInfo.processInfo.environment
            let runtimeBin = runtime.nodeURL.deletingLastPathComponent().path
            let inheritedPath = environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(runtimeBin):\(inheritedPath)"
            process.environment = environment
            process.standardOutput = harnessLogHandle
            process.standardError = harnessLogHandle
            process.terminationHandler = { [weak self] terminatedProcess in
                DispatchQueue.main.async {
                    guard let self, !self.isTerminating else { return }
                    self.probeHarness { isReady in
                        if isReady {
                            self.loadHarnessPage()
                        } else if !self.harnessPageHasLoaded {
                            self.showStartup(
                                status: "Harness 启动失败",
                                detail: "进程已退出（代码 \(terminatedProcess.terminationStatus)）。请查看日志后重试。",
                                isError: true
                            )
                        }
                    }
                }
            }

            try process.run()
            harnessProcess = process
            harnessWasStartedByThisApp = true
            showStartup(
                status: "正在启动 DeepSeek Harness",
                detail: "正在运行 \(harnessPackageSpecifier)\n工作区：\(workspaceURL.path)",
                isError: false
            )
            beginProbeLoop()
        } catch {
            appendLog("Native launcher error: \(error.localizedDescription)\n")
            showStartup(status: "无法启动 Harness", detail: error.localizedDescription, isError: true)
        }
    }

    private func resolveWorkspaceURL() -> URL {
        if let savedPath = UserDefaults.standard.string(forKey: workspaceDefaultsKey), !savedPath.isEmpty {
            return URL(fileURLWithPath: savedPath, isDirectory: true).standardizedFileURL
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("DeepSeek Harness Workspace", isDirectory: true)
    }

    private func ensureWorkspaceExists() throws {
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }

    private func confirmOfficialPackageDownloadIfNeeded() -> Bool {
        if UserDefaults.standard.bool(forKey: packageApprovalDefaultsKey) {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "下载并启动官方 DeepSeek Harness？"
        alert.informativeText = "此非官方启动器不内置 Harness。继续后，npx 将从 npm 获取并运行 \(harnessPackageSpecifier)。API Key 不会包含在 App 中，请稍后在 Harness 的 Settings → Models 中自行配置。"
        alert.addButton(withTitle: "下载并启动")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: packageApprovalDefaultsKey)
        return true
    }

    private func discoverNodeRuntime() -> (runtime: NodeRuntime?, detail: String) {
        var directories: [URL] = []
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        if let inheritedPath = ProcessInfo.processInfo.environment["PATH"] {
            directories.append(contentsOf: inheritedPath.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
            })
        }

        directories.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            home.appendingPathComponent(".volta/bin", isDirectory: true),
            home.appendingPathComponent(".local/bin", isDirectory: true),
            home.appendingPathComponent(".asdf/shims", isDirectory: true),
            home.appendingPathComponent(".local/share/fnm/current/bin", isDirectory: true)
        ])

        let nvmRoot = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versions = try? fileManager.contentsOfDirectory(
            at: nvmRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            directories.append(contentsOf: versions.sorted { $0.lastPathComponent > $1.lastPathComponent }.map {
                $0.appendingPathComponent("bin", isDirectory: true)
            })
        }

        var seen = Set<String>()
        var unsupportedVersions: [String] = []

        for directory in directories {
            let standardized = directory.standardizedFileURL.path
            guard seen.insert(standardized).inserted else { continue }

            let nodeURL = directory.appendingPathComponent("node", isDirectory: false)
            let npxURL = directory.appendingPathComponent("npx", isDirectory: false)
            guard fileManager.isExecutableFile(atPath: nodeURL.path),
                  fileManager.isExecutableFile(atPath: npxURL.path),
                  let version = readNodeVersion(at: nodeURL) else { continue }

            if isSupportedNodeVersion(version) {
                return (NodeRuntime(nodeURL: nodeURL, npxURL: npxURL, version: version), "")
            }
            unsupportedVersions.append(version)
        }

        if let found = unsupportedVersions.first {
            return (nil, "检测到 Node.js \(found)，但当前 Harness 需要 Node.js 22.19+ 或 24+。升级 Node.js 后再点“重新尝试”。")
        }
        return (nil, "未找到 npx。请先安装 Node.js 22.19+ 或 24+，然后重新打开 App。官方说明：github.com/deepseek-ai/deepseek-harness")
    }

    private func readNodeVersion(at nodeURL: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = nodeURL
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func isSupportedNodeVersion(_ rawVersion: String) -> Bool {
        let version = rawVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = version.split(separator: ".")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else { return false }
        return major >= 24 || (major == 22 && minor >= 19)
    }

    private func prepareLogFile() throws {
        let directory = logURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        harnessLogHandle = handle
    }

    private func appendLog(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        try? harnessLogHandle?.write(contentsOf: data)
    }

    private func beginProbeLoop() {
        probeTimer?.invalidate()
        probeAttempts = 0
        probeTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(probeTick(_:)), userInfo: nil, repeats: true)
        probeTimer?.tolerance = 0.08
        probeTick(probeTimer as Any)
    }

    @objc private func probeTick(_ sender: Any?) {
        guard !probeInFlight else { return }
        probeAttempts += 1

        if probeAttempts > maximumProbeAttempts {
            probeTimer?.invalidate()
            probeTimer = nil
            showStartup(
                status: "Harness 尚未就绪",
                detail: "等待 90 秒后仍未收到 HTTP 200。请查看日志后重试。",
                isError: true
            )
            return
        }

        probeHarness { [weak self] isReady in
            guard let self else { return }
            if isReady {
                self.probeTimer?.invalidate()
                self.probeTimer = nil
                self.loadHarnessPage()
            }
        }
    }

    private func probeHarness(completion: @escaping (Bool) -> Void) {
        guard !probeInFlight else {
            completion(false)
            return
        }
        probeInFlight = true

        var components = URLComponents(url: harnessURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "_native_probe", value: String(Int(Date().timeIntervalSince1970 * 1_000)))
        ]

        var request = URLRequest(url: components?.url ?? harnessURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 1.5
        request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        probeSession.dataTask(with: request) { [weak self] data, response, _ in
            let statusIsReady = (response as? HTTPURLResponse)?.statusCode == 200
            let pagePrefix = data.flatMap { String(data: $0.prefix(32_768), encoding: .utf8) }?.lowercased() ?? ""
            let identityIsReady = pagePrefix.contains("deepseek") || pagePrefix.contains("dsh-web")
            let isReady = statusIsReady && identityIsReady
            DispatchQueue.main.async {
                self?.probeInFlight = false
                completion(isReady)
            }
        }.resume()
    }

    private func loadHarnessPage() {
        guard !harnessPageHasLoaded else { return }
        harnessPageHasLoaded = true
        showStartup(status: "正在载入工作台", detail: "本机服务已就绪（HTTP 200）", isError: false)
        var request = URLRequest(url: harnessURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
    }

    private func showStartup(status: String, detail: String, isError: Bool) {
        startupView.isHidden = false
        webView.isHidden = true
        statusLabel.stringValue = status
        detailLabel.stringValue = detail
        progressIndicator.isHidden = isError
        retryButton.isHidden = !isError
        logButton.isHidden = !isError
        if isError {
            progressIndicator.stopAnimation(nil)
        } else {
            progressIndicator.startAnimation(nil)
        }
    }

    private func isLocalHarnessURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return (host == "127.0.0.1" || host == "localhost") && (url.port == nil || url.port == 3080)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startupView.isHidden = true
        webView.isHidden = false
        window.title = appDisplayName
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        harnessPageHasLoaded = false
        showStartup(status: "页面载入失败", detail: error.localizedDescription, isError: true)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        harnessPageHasLoaded = false
        showStartup(status: "无法连接本机 Harness", detail: error.localizedDescription, isError: true)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                if !isLocalHarnessURL(url) {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            } else if scheme != "about" && scheme != "blob" && scheme != "data" {
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else { return nil }
        let scheme = url.scheme?.lowercased()
        if isLocalHarnessURL(url) {
            webView.load(navigationAction.request)
        } else if scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
