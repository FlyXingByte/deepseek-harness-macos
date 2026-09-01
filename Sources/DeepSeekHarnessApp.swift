import AppKit
import Darwin
import Foundation
import WebKit

private let appDisplayName = "DeepSeek Harness"
private let harnessBaseURL = URL(string: "http://127.0.0.1:3080/")!
private let harnessPackageName = "@deepseek-ai/dsh"
private let defaultHarnessPackageVersion = "0.1.2-alpha.3"
private let verifiedFallbackHarnessPackageVersion = "0.1.1-rc.2"
private let minimumRollbackHarnessPackageVersion = "0.1.0-rc.6"
private let harnessDistTagsURL = URL(string: "https://registry.npmjs.org/-/package/%40deepseek-ai%2Fdsh/dist-tags")!
private let harnessProjectURL = URL(string: "https://github.com/deepseek-ai/deepseek-harness")!
private let maximumProbeAttempts = 180
private let nativeChromeMessageName = "harnessNativeChrome"
private let defaultChromeColor = NSColor(srgbRed: 0.018, green: 0.043, blue: 0.115, alpha: 1)

/// Injected before the page runs: removes the browser tells the Harness Web UI inherits
/// from running inside WebKit (hand cursors on controls, selectable chrome labels,
/// draggable links and images, rubber-band overscroll, web-styled scrollbars).
private let nativeChromeStyleScript = """
(function () {
    const id = 'harness-native-chrome-style';
    if (document.getElementById(id)) { return; }
    const style = document.createElement('style');
    style.id = id;
    style.textContent = [
        'html, body { overscroll-behavior: none; -webkit-font-smoothing: antialiased; }',
        'button, [role="button"], [role="tab"], [role="menuitem"], [role="option"], [role="switch"], [role="radio"], [role="checkbox"], [data-slot="button"], summary, label, select, a[href], .cursor-pointer { cursor: default !important; }',
        'input, textarea, [contenteditable="true"], [contenteditable=""] { cursor: text !important; }',
        'button, [role="button"], [role="tab"], [role="menuitem"], [data-slot="button"], nav, label, summary, select, svg { -webkit-user-select: none !important; user-select: none !important; }',
        'input, textarea, [contenteditable="true"], [contenteditable=""] { -webkit-user-select: text !important; user-select: text !important; }',
        'a[href], img, svg, video, canvas { -webkit-user-drag: none !important; }',
        '::-webkit-scrollbar { width: 11px; height: 11px; background: transparent; }',
        '::-webkit-scrollbar-track { background: transparent; }',
        '::-webkit-scrollbar-thumb { background-color: rgba(142, 142, 147, 0.42); background-clip: content-box; border: 3px solid transparent; border-radius: 8px; }',
        '::-webkit-scrollbar-thumb:hover { background-color: rgba(142, 142, 147, 0.66); }',
        '::-webkit-scrollbar-corner { background: transparent; }'
    ].join('\\n');
    (document.head || document.documentElement).appendChild(style);
    document.addEventListener('DOMContentLoaded', function () {
        if (document.head && style.parentNode !== document.head) { document.head.appendChild(style); }
    }, { once: true });
})();
"""

/// Reports the page background to the native side so the title bar, window background and
/// system appearance stay one continuous surface with the Harness UI instead of framing it.
private let nativeChromeThemeScript = """
(function () {
    const bridge = window.webkit
        && window.webkit.messageHandlers
        && window.webkit.messageHandlers.harnessNativeChrome;
    if (!bridge) { return; }

    let lastReported = '';

    function measure(value) {
        if (!value) { return null; }
        const canvas = document.createElement('canvas');
        canvas.width = 1;
        canvas.height = 1;
        const context = canvas.getContext('2d');
        if (!context) { return null; }
        context.clearRect(0, 0, 1, 1);
        try {
            context.fillStyle = value;
        } catch (error) {
            return null;
        }
        context.fillRect(0, 0, 1, 1);
        let pixel;
        try {
            pixel = context.getImageData(0, 0, 1, 1).data;
        } catch (error) {
            return null;
        }
        if (pixel[3] < 24) { return null; }
        return { r: pixel[0], g: pixel[1], b: pixel[2] };
    }

    function backgroundOf(element) {
        if (!element) { return null; }
        return measure(window.getComputedStyle(element).backgroundColor);
    }

    function resolve() {
        const candidates = [document.documentElement, document.body];
        if (document.body) {
            candidates.push(document.body.firstElementChild);
            candidates.push(document.elementFromPoint(Math.round(window.innerWidth / 2), 2));
        }
        for (const candidate of candidates) {
            const color = backgroundOf(candidate);
            if (color) { return color; }
        }
        return null;
    }

    function report() {
        const color = resolve();
        if (!color) { return; }
        const key = color.r + ',' + color.g + ',' + color.b;
        if (key === lastReported) { return; }
        lastReported = key;
        bridge.postMessage(color);
    }

    let pending = 0;
    function schedule() {
        if (pending) { return; }
        pending = window.setTimeout(function () {
            pending = 0;
            report();
        }, 120);
    }

    report();

    const observer = new MutationObserver(schedule);
    const watched = { attributes: true, attributeFilter: ['class', 'style', 'data-theme'] };
    observer.observe(document.documentElement, watched);
    if (document.body) { observer.observe(document.body, watched); }
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', schedule);
    window.addEventListener('focus', schedule);
    window.setInterval(report, 5000);
})();
"""

private let nativeContextMenuActions: Set<Selector> = [
    #selector(NSText.cut(_:)),
    #selector(NSText.copy(_:)),
    #selector(NSText.paste(_:)),
    #selector(NSText.selectAll(_:)),
    #selector(NSText.delete(_:)),
    #selector(NSTextView.pasteAsPlainText(_:)),
    Selector(("undo:")),
    Selector(("redo:"))
]

/// Keeps only the editing commands a native app would offer, so right-clicking never exposes
/// Reload / Back / Forward / Open in New Window / Inspect Element.
final class HarnessWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        for item in menu.items.reversed() {
            let identifier = item.identifier?.rawValue ?? ""
            let isCopyVariant = identifier.hasPrefix("WKMenuItemIdentifierCopy")
            let isEditingCommand = item.action.map { nativeContextMenuActions.contains($0) } ?? false
            if !isCopyVariant && !isEditingCommand {
                menu.removeItem(item)
            }
        }

        while let first = menu.items.first, first.isSeparatorItem {
            menu.removeItem(first)
        }
        while let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
    }
}

private func prefersDarkChrome(red: Double, green: Double, blue: Double, currentlyDark: Bool) -> Bool {
    let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
    if luminance < 0.42 { return true }
    if luminance > 0.58 { return false }
    return currentlyDark
}

private struct SemanticVersion: Comparable {
    private enum PrereleaseIdentifier: Equatable {
        case numeric(Int)
        case text(String)
    }

    let major: Int
    let minor: Int
    let patch: Int
    private let prerelease: [PrereleaseIdentifier]

    init?(_ rawValue: String) {
        let pattern = #"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"#
        guard rawValue.range(of: pattern, options: .regularExpression) != nil else { return nil }

        let withoutBuildMetadata = rawValue.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let releaseAndPrerelease = withoutBuildMetadata.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let releaseParts = releaseAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard releaseParts.count == 3,
              let major = Int(releaseParts[0]),
              let minor = Int(releaseParts[1]),
              let patch = Int(releaseParts[2]) else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch
        if releaseAndPrerelease.count == 2 {
            prerelease = releaseAndPrerelease[1].split(separator: ".").map { component in
                if let numericValue = Int(component) {
                    return .numeric(numericValue)
                }
                return .text(String(component))
            }
        } else {
            prerelease = []
        }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        for index in 0..<Swift.min(lhs.prerelease.count, rhs.prerelease.count) {
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }

            switch (left, right) {
            case let (.numeric(leftValue), .numeric(rightValue)):
                return leftValue < rightValue
            case (.numeric, .text):
                return true
            case (.text, .numeric):
                return false
            case let (.text(leftValue), .text(rightValue)):
                return leftValue < rightValue
            }
        }

        return lhs.prerelease.count < rhs.prerelease.count
    }
}

private enum HarnessUpdateChannel: String {
    case defaultRelease = "default"
    case alpha = "alpha"

    var displayName: String {
        switch self {
        case .defaultRelease: return "默认（latest / next）"
        case .alpha: return "Alpha 实验"
        }
    }

    var candidateTags: [String] {
        switch self {
        case .defaultRelease: return ["latest", "next"]
        // Include the default tags as well so an alpha user is offered a later
        // stable release instead of remaining on a lower prerelease forever.
        case .alpha: return ["latest", "next", "alpha"]
        }
    }
}

private func newestOfficialHarnessVersion(
    in distTags: [String: String],
    channel: HarnessUpdateChannel
) -> String? {
    let candidates = channel.candidateTags.map { distTags[$0] }
        .compactMap { $0 }
        .compactMap { rawValue -> (String, SemanticVersion)? in
            guard let version = SemanticVersion(rawValue) else { return nil }
            return (rawValue, version)
        }

    return candidates.max { $0.1 < $1.1 }?.0
}

private struct HarnessOutputInspection {
    let sanitizedLine: String
    let authenticationURL: URL?
}

/// Redacts the process-scoped browser token defensively from every launcher log write.
/// The raw token is only kept in memory long enough for WKWebView to exchange it for
/// the official HttpOnly browser-session cookie.
private func redactedHarnessLogText(_ text: String) -> String {
    text.replacingOccurrences(
        of: #"([?&]token=)[^&\s\"'<>]+"#,
        with: "$1<redacted>",
        options: .regularExpression
    )
}

/// Accepts only the exact readiness line and local origin emitted by `dsh web`.
/// A plugin or unrelated process cannot redirect the native window by printing an
/// arbitrary URL into the shared process output stream.
private func inspectHarnessOutputLine(_ line: String, expectedBaseURL: URL) -> HarnessOutputInspection {
    let sanitized = redactedHarnessLogText(line)
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "dsh web: "
    guard trimmed.hasPrefix(prefix) else {
        return HarnessOutputInspection(sanitizedLine: sanitized, authenticationURL: nil)
    }

    let rawURL = String(trimmed.dropFirst(prefix.count))
    guard let url = URL(string: rawURL),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          url.scheme?.lowercased() == expectedBaseURL.scheme?.lowercased(),
          url.host?.lowercased() == expectedBaseURL.host?.lowercased(),
          url.port == expectedBaseURL.port,
          url.user == nil,
          url.password == nil,
          url.fragment == nil,
          url.path == expectedBaseURL.path else {
        return HarnessOutputInspection(sanitizedLine: sanitized, authenticationURL: nil)
    }

    let tokenItems = (components.queryItems ?? []).filter { $0.name == "token" }
    guard tokenItems.count == 1,
          (components.queryItems ?? []).count == 1,
          let token = tokenItems[0].value,
          token.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil else {
        return HarnessOutputInspection(sanitizedLine: sanitized, authenticationURL: nil)
    }

    return HarnessOutputInspection(sanitizedLine: sanitized, authenticationURL: url)
}

private enum HarnessProbeResult: Equatable {
    case ready
    case authenticationRequired
    case occupiedUnknown
    case unavailable
}

/// Drains the child process continuously on a private serial queue. Raw bytes are
/// buffered until a newline before UTF-8 decoding, so a multibyte log character split
/// across pipe chunks cannot drop the following readiness URL. All writes to the shared
/// log handle also pass through this queue while the process is alive.
private final class HarnessProcessOutputRelay {
    let pipe = Pipe()

    private let queue = DispatchQueue(label: "com.flyx.deepseek-harness.output-relay")
    private let logHandle: FileHandle
    private let expectedBaseURL: URL
    private var buffer = Data()
    private var capturedAuthenticationURL: URL?

    init(logHandle: FileHandle, expectedBaseURL: URL) {
        self.logHandle = logHandle
        self.expectedBaseURL = expectedBaseURL
    }

    func attach(to process: Process) {
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async {
                self?.consume(data)
            }
        }
    }

    func appendLog(_ text: String) {
        queue.async { [weak self] in
            self?.write(redactedHarnessLogText(text))
        }
    }

    func authenticationURL() -> URL? {
        queue.sync { capturedAuthenticationURL }
    }

    /// Call only after the child has exited, so reading to EOF cannot block.
    func closeAfterProcessExit() {
        pipe.fileHandleForReading.readabilityHandler = nil
        let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
        queue.sync {
            consume(remaining)
            flush()
        }
    }

    func invalidateWithoutDraining() {
        pipe.fileHandleForReading.readabilityHandler = nil
        queue.sync { flush() }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else {
            flush()
            return
        }
        buffer.append(data)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            handleLineData(Data(lineData))
        }
    }

    private func flush() {
        guard !buffer.isEmpty else { return }
        let lineData = buffer
        buffer.removeAll(keepingCapacity: false)
        handleLineData(lineData)
    }

    private func handleLineData(_ data: Data) {
        let line = String(decoding: data, as: UTF8.self)
        let inspection = inspectHarnessOutputLine(line, expectedBaseURL: expectedBaseURL)
        if let authenticationURL = inspection.authenticationURL {
            capturedAuthenticationURL = authenticationURL
        }
        write(inspection.sanitizedLine + "\n")
    }

    private func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        try? logHandle.write(contentsOf: data)
    }
}

private let dshHomeEnvironmentKey = "DSH_HOME"
private let dshHomeDirectoryName = ".dsh"
private let harnessSessionsDirectoryName = "sessions"
private let harnessStoragesDirectoryName = "storages"
private let harnessWorkspaceRegistryFileName = "workspace.json"
private let legacyHarnessSessionCacheFileName = "session_projcache.json"
private let harnessSessionCacheDirectoryName = "session_projcache"
private let harnessSessionCacheRecordsDirectoryName = "sessions"
private let harnessStorageBackupLimit = 5

/// Expands the tilde prefixes the official harness accepts in `$DSH_HOME`.
private func expandHarnessHomePath(_ path: String, home: URL) -> String {
    if path == "~" { return home.path }
    if path.hasPrefix("~/") {
        return home.appendingPathComponent(String(path.dropFirst(2))).path
    }
    return path
}

/// Resolves the single root the official Harness keeps user data under: `$DSH_HOME`
/// when it names something, otherwise `~/.dsh`. Mirrors `@deepseek-ai/dsh-home-paths`,
/// so the launcher reads exactly the files the running kernel writes.
private func resolveHarnessHomeURL(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
) -> URL {
    let configured = environment[dshHomeEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !configured.isEmpty else {
        return home.appendingPathComponent(dshHomeDirectoryName, isDirectory: true).standardizedFileURL
    }
    return URL(fileURLWithPath: expandHarnessHomePath(configured, home: home), isDirectory: true).standardizedFileURL
}

/// The archived sessions the kernel hides from the sidebar, in registry order and
/// without duplicates. Archiving never touches the transcript, so these ids are the
/// exact set whose records the user asked to be gone rather than merely hidden.
private func archivedSessionIds(in registry: [String: Any]) -> [String] {
    guard let global = registry["global"] as? [String: Any],
          let storedIds = global["archivedSessionIds"] as? [Any] else { return [] }

    var seen = Set<String>()
    var ids: [String] = []
    for value in storedIds {
        guard let id = value as? String, !id.isEmpty, seen.insert(id).inserted else { continue }
        ids.append(id)
    }
    return ids
}

private func filteredSessionIdList(_ values: [Any], removing ids: Set<String>) -> [Any] {
    values.filter { value in
        guard let id = value as? String else { return true }
        return !ids.contains(id)
    }
}

/// Drops the removed sessions from the workspace registry: the registry-global archive
/// set and every workspace's ordered member list. Unknown keys are copied through, so a
/// newer kernel's registry survives the rewrite.
private func workspaceRegistry(_ registry: [String: Any], removingSessionIds ids: Set<String>) -> [String: Any] {
    guard !ids.isEmpty else { return registry }
    var updated = registry

    if var global = registry["global"] as? [String: Any] {
        if let archived = global["archivedSessionIds"] as? [Any] {
            global["archivedSessionIds"] = filteredSessionIdList(archived, removing: ids)
        }
        updated["global"] = global
    }

    if var tables = registry["tables"] as? [String: Any],
       var workspaces = tables["workspaces"] as? [String: Any] {
        for (workspaceId, value) in workspaces {
            guard var workspace = value as? [String: Any],
                  let sessionIds = workspace["sessionIds"] as? [Any] else { continue }
            workspace["sessionIds"] = filteredSessionIdList(sessionIds, removing: ids)
            workspaces[workspaceId] = workspace
        }
        tables["workspaces"] = workspaces
        updated["tables"] = tables
    }

    return updated
}

/// Drops the removed sessions from the projection cache that backs sidebar titles and
/// statistics; leaving them behind would keep deleted conversations named in the UI.
private func sessionProjectionCache(_ cache: [String: Any], removingSessionIds ids: Set<String>) -> [String: Any] {
    guard !ids.isEmpty,
          var tables = cache["tables"] as? [String: Any],
          var sessions = tables["sessions"] as? [String: Any] else { return cache }

    for id in ids {
        sessions.removeValue(forKey: id)
    }
    tables["sessions"] = sessions
    var updated = cache
    updated["tables"] = tables
    return updated
}

private func storageUnit(_ storage: [String: Any], matchesName name: String, version: Int) -> Bool {
    guard let unit = storage["unit"] as? [String: Any],
          unit["name"] as? String == name,
          let storedVersion = unit["version"] as? NSNumber,
          storedVersion.doubleValue == Double(version) else { return false }
    return true
}

private func isRegularFileWithoutSymlinks(_ url: URL) -> Bool {
    let file = url.standardizedFileURL
    guard file.resolvingSymlinksInPath().path == file.path,
          let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
        return false
    }
    return values.isRegularFile == true && values.isSymbolicLink != true
}

private struct ProjectionCacheRecordScan {
    let records: [URL]
    let failures: [String]

    static let empty = ProjectionCacheRecordScan(records: [], failures: [])
}

private func scanProjectionCacheRecords(
    in root: URL,
    matching ids: Set<String>,
    fileManager: FileManager = .default
) -> ProjectionCacheRecordScan {
    let standardizedRoot = root.standardizedFileURL
    guard fileManager.fileExists(atPath: standardizedRoot.path) else { return .empty }
    guard standardizedRoot.resolvingSymlinksInPath().path == standardizedRoot.path,
          let rootValues = try? standardizedRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
          rootValues.isDirectory == true,
          rootValues.isSymbolicLink != true else {
        return ProjectionCacheRecordScan(records: [], failures: ["session_projcache/sessions 不是安全的真实目录"])
    }
    guard let candidates = try? fileManager.contentsOfDirectory(
        at: standardizedRoot,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
    ) else {
        return ProjectionCacheRecordScan(records: [], failures: ["无法读取 session_projcache/sessions"])
    }

    var records: [URL] = []
    var failures: [String] = []
    for record in candidates {
        guard record.pathExtension == "json",
              ids.contains(record.deletingPathExtension().lastPathComponent) else { continue }
        let standardized = record.standardizedFileURL
        guard standardized.deletingLastPathComponent().path == standardizedRoot.path,
              standardized.resolvingSymlinksInPath().path == standardized.path,
              let values = try? standardized.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              projectionCacheRecordIsVersion4(standardized) else {
            failures.append("\(record.lastPathComponent)：不是受支持的普通 v4 投影缓存文件")
            continue
        }
        records.append(standardized)
    }
    return ProjectionCacheRecordScan(
        records: records.sorted { $0.path < $1.path },
        failures: failures.sorted()
    )
}

private func projectionCacheRecordIsVersion4(_ url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url),
          let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let version = document["version"] as? NSNumber,
          version.doubleValue == 4,
          document["record"] is [String: Any] else { return false }
    return true
}

/// What one cleanup would remove, measured before the user is asked to confirm.
private struct ArchivedSessionCleanupPlan {
    let sessionIds: [String]
    /// Transcript directories that exist on disk. Archived sessions that never wrote a
    /// transcript have no directory and only leave registry entries behind.
    let directories: [URL]
    /// Alpha.3 stores each derived projection cache record in its own JSON file.
    /// These are backed up and removed together with the authoritative transcript.
    let projectionCacheRecords: [URL]
    let validationFailures: [String]
    let byteSize: Int64

    static let empty = ArchivedSessionCleanupPlan(
        sessionIds: [],
        directories: [],
        projectionCacheRecords: [],
        validationFailures: [],
        byteSize: 0
    )

    var isEmpty: Bool { sessionIds.isEmpty }
    var isValid: Bool { validationFailures.isEmpty }
}

private struct TrashedPathMove {
    let originalURL: URL
    let trashURL: URL
    let byteSize: Int64
}

/// What one cleanup actually removed, reported back to the user afterwards.
private struct ArchivedSessionCleanupOutcome {
    var trashedDirectories = 0
    var freedBytes: Int64 = 0
    var removedRegistryEntries = 0
    var removedProjectionCacheRecords = 0
    var backupDirectory: URL?
    var failures: [String] = []
}

private enum HarnessUpdateError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case invalidMetadata

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "npm 官方服务返回了无法识别的响应。"
        case let .httpStatus(statusCode):
            return "npm 官方服务返回 HTTP \(statusCode)。"
        case .invalidMetadata:
            return "npm 官方版本信息中没有可验证的 latest 或 next 版本。"
        }
    }
}

private struct NodeRuntime {
    let nodeURL: URL
    let npxURL: URL
    let version: String
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate,
                         WKScriptMessageHandler, NSMenuItemValidation {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var startupView: NSView!
    private var statusLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!
    private var retryButton: NSButton!
    private var logButton: NSButton!
    private var harnessVersionMenuItem: NSMenuItem!
    private var harnessRunningVersionMenuItem: NSMenuItem!
    private var harnessUpdateChannelMenuItem: NSMenuItem!
    private var checkHarnessUpdateMenuItem: NSMenuItem!
    private var rollBackHarnessMenuItem: NSMenuItem!
    private var purgeArchivedSessionsMenuItem: NSMenuItem!

    private var probeTimer: Timer?
    private var probeAttempts = 0
    private var probeInFlight = false
    private var harnessProcess: Process?
    private var harnessLogHandle: FileHandle?
    private var harnessOutputRelay: HarnessProcessOutputRelay?
    private var pendingHarnessAuthenticationURL: URL?
    private var validatedMainFrameHarnessResponse = false
    private var harnessWasStartedByThisApp = false
    private var activeOwnedHarnessVersion: String?
    private var restartHarnessAfterTermination = false
    private var isTerminating = false
    private var harnessPageHasLoaded = false
    private var isCheckingForHarnessUpdate = false
    private var pendingArchivedSessionCleanup: ArchivedSessionCleanupPlan?
    private let workspaceDefaultsKey = "HarnessWorkspacePath"
    private let packageApprovalDefaultsKey = "ApprovedOfficialHarnessPackageDownload"
    private let harnessVersionDefaultsKey = "SelectedOfficialHarnessPackageVersion"
    private let harnessVersionHistoryDefaultsKey = "OfficialHarnessPackageVersionHistory"
    private let harnessUpdateChannelDefaultsKey = "OfficialHarnessUpdateChannel"
    private let lastKnownGoodHarnessVersionDefaultsKey = "LastKnownGoodOfficialHarnessPackageVersion"
    private let harnessVersionHistoryLimit = 10
    private let pageZoomDefaultsKey = "HarnessPageZoom"
    private let minimumPageZoom: CGFloat = 0.75
    private let maximumPageZoom: CGFloat = 2.0
    private let pageZoomStep: CGFloat = 0.1
    private var currentPageZoom: CGFloat = 1.0
    private var chromeColor: NSColor = defaultChromeColor
    private var chromeIsDark = true
    private var chromeComponents: (red: Double, green: Double, blue: Double) = (0.018, 0.043, 0.115)
    private lazy var workspaceURL: URL = resolveWorkspaceURL()
    private lazy var selectedHarnessPackageVersion: String = resolveSelectedHarnessPackageVersion()
    private lazy var harnessPackageVersionHistory: [String] = resolveHarnessPackageVersionHistory()
    private lazy var harnessUpdateChannel: HarnessUpdateChannel = resolveHarnessUpdateChannel()
    private lazy var lastKnownGoodHarnessPackageVersion: String = resolveLastKnownGoodHarnessPackageVersion()
    private var pendingHarnessSwitchFromVersion: String?
    private var isAutomaticHarnessRollback = false
    private var isHarnessTransitionInProgress = false
    private var previousHarnessPackageVersion: String? {
        harnessPackageVersionHistory.last
    }
    private var harnessPackageSpecifier: String {
        "\(harnessPackageName)@\(selectedHarnessPackageVersion)"
    }

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

    private lazy var updateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Cache-Control": "no-cache, no-store, max-age=0"
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
        updateSession.invalidateAndCancel()

        if harnessWasStartedByThisApp, let process = harnessProcess, process.isRunning {
            appendLog("Stopping Harness because the native app is quitting.\n")
            process.terminate()
        }

        closeHarnessOutputCapture()
        closeHarnessLogHandle()
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appDisplayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = chromeColor
        window.minSize = NSSize(width: 900, height: 600)
        window.center()
        window.setFrameAutosaveName("DeepSeekHarnessMainWindow")
        window.tabbingMode = .disallowed
        window.delegate = self

        let rootView = NSView(frame: contentRect)
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = chromeColor.cgColor
        window.contentView = rootView

        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: nativeChromeStyleScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        contentController.addUserScript(WKUserScript(
            source: nativeChromeThemeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        contentController.add(self, name: nativeChromeMessageName)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController = contentController

        webView = HarnessWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.underPageBackgroundColor = chromeColor
        webView.wantsLayer = true
        webView.isHidden = true
        rootView.addSubview(webView)

        startupView = makeStartupView()
        startupView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(startupView)

        currentPageZoom = storedPageZoom()
        applyPageZoom(currentPageZoom, persist: false)

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
        view.layer?.backgroundColor = chromeColor.cgColor

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown

        statusLabel = NSTextField(labelWithString: "正在启动 DeepSeek Harness")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 25, weight: .semibold)
        statusLabel.alignment = .center

        detailLabel = NSTextField(labelWithString: "正在连接本机服务…")
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
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
        refreshStartupPalette()

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
        appMenu.addItem(.separator())
        harnessVersionMenuItem = NSMenuItem(title: "已选内核：\(selectedHarnessPackageVersion)", action: nil, keyEquivalent: "")
        harnessVersionMenuItem.isEnabled = false
        appMenu.addItem(harnessVersionMenuItem)
        harnessRunningVersionMenuItem = NSMenuItem(title: "运行内核：尚未连接", action: nil, keyEquivalent: "")
        harnessRunningVersionMenuItem.isEnabled = false
        appMenu.addItem(harnessRunningVersionMenuItem)
        harnessUpdateChannelMenuItem = NSMenuItem(
            title: "使用 Alpha 实验更新通道",
            action: #selector(toggleHarnessUpdateChannel(_:)),
            keyEquivalent: ""
        )
        harnessUpdateChannelMenuItem.target = self
        appMenu.addItem(harnessUpdateChannelMenuItem)
        checkHarnessUpdateMenuItem = NSMenuItem(title: "检查并更新 Harness 内核…", action: #selector(checkForHarnessUpdate(_:)), keyEquivalent: "")
        checkHarnessUpdateMenuItem.target = self
        appMenu.addItem(checkHarnessUpdateMenuItem)
        rollBackHarnessMenuItem = NSMenuItem(
            title: rollBackHarnessMenuItemTitle,
            action: #selector(rollBackToPreviousHarnessVersion(_:)),
            keyEquivalent: ""
        )
        rollBackHarnessMenuItem.target = self
        appMenu.addItem(rollBackHarnessMenuItem)
        appMenu.addItem(.separator())
        purgeArchivedSessionsMenuItem = NSMenuItem(
            title: purgeArchivedSessionsMenuItemTitle(count: 0),
            action: #selector(purgeArchivedSessions(_:)),
            keyEquivalent: ""
        )
        purgeArchivedSessionsMenuItem.target = self
        appMenu.addItem(purgeArchivedSessionsMenuItem)
        appMenu.addItem(.separator())
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
        viewMenu.addItem(.separator())
        let increaseSizeItem = NSMenuItem(title: "增大字体", action: #selector(increasePageZoom(_:)), keyEquivalent: "+")
        increaseSizeItem.keyEquivalentModifierMask = [.command]
        increaseSizeItem.target = self
        viewMenu.addItem(increaseSizeItem)
        let decreaseSizeItem = NSMenuItem(title: "缩小字体", action: #selector(decreasePageZoom(_:)), keyEquivalent: "-")
        decreaseSizeItem.keyEquivalentModifierMask = [.command]
        decreaseSizeItem.target = self
        viewMenu.addItem(decreaseSizeItem)
        let actualSizeItem = NSMenuItem(title: "实际大小", action: #selector(resetPageZoom(_:)), keyEquivalent: "0")
        actualSizeItem.keyEquivalentModifierMask = [.command]
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
        refreshHarnessVersionMenuItems()
    }

    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
        let runningVersion = harnessWasStartedByThisApp
            ? (activeOwnedHarnessVersion ?? "正在启动")
            : (harnessPageHasLoaded ? "外部服务（版本未知）" : "尚未连接")
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appDisplayName,
            .applicationVersion: version,
            .version: "非官方原生窗口版 · 已选 \(selectedHarnessPackageVersion) · 运行 \(runningVersion)",
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === checkHarnessUpdateMenuItem {
            return !isCheckingForHarnessUpdate && !isHarnessTransitionInProgress
        }
        if menuItem === harnessUpdateChannelMenuItem {
            return !isCheckingForHarnessUpdate && !isHarnessTransitionInProgress
        }
        if menuItem === rollBackHarnessMenuItem {
            return !isCheckingForHarnessUpdate && !isHarnessTransitionInProgress && previousHarnessPackageVersion != nil
        }
        if menuItem === purgeArchivedSessionsMenuItem {
            // Reading only the registry keeps this cheap enough to run each time the menu opens;
            // transcript sizes are measured later, once the user asks for the cleanup itself.
            let archivedCount = archivedSessionIds(in: loadHarnessStorage(at: workspaceRegistryURL) ?? [:]).count
            menuItem.title = purgeArchivedSessionsMenuItemTitle(count: archivedCount)
            return !isHarnessTransitionInProgress && archivedCount > 0
        }
        return true
    }

    private func refreshHarnessVersionMenuItems() {
        harnessVersionMenuItem?.title = "已选内核：\(selectedHarnessPackageVersion)"
        if harnessWasStartedByThisApp, let activeOwnedHarnessVersion {
            harnessRunningVersionMenuItem?.title = "运行内核：\(activeOwnedHarnessVersion)（本 App）"
        } else if harnessPageHasLoaded {
            harnessRunningVersionMenuItem?.title = "运行内核：外部服务（版本未知）"
        } else {
            harnessRunningVersionMenuItem?.title = "运行内核：尚未连接"
        }
        harnessUpdateChannelMenuItem?.state = harnessUpdateChannel == .alpha ? .on : .off
        checkHarnessUpdateMenuItem?.title = isCheckingForHarnessUpdate
            ? "正在检查官方更新…"
            : "检查\(harnessUpdateChannel.displayName)通道更新…"
        rollBackHarnessMenuItem?.title = rollBackHarnessMenuItemTitle
        rollBackHarnessMenuItem?.isEnabled = previousHarnessPackageVersion != nil
        NSApp.mainMenu?.update()
    }

    private var rollBackHarnessMenuItemTitle: String {
        guard let previousVersion = previousHarnessPackageVersion else {
            return "回退到上一版内核"
        }
        return "回退到上一版内核 \(previousVersion)"
    }

    @objc private func toggleHarnessUpdateChannel(_ sender: Any?) {
        guard !isCheckingForHarnessUpdate else { return }

        if harnessUpdateChannel == .alpha {
            setHarnessUpdateChannel(.defaultRelease)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "启用 Alpha 实验更新通道？"
        alert.informativeText = "Alpha 版本可能包含破坏兼容性的变化。回退可以恢复旧执行版本，但不能自动逆转官方内核已经写入的数据格式变化。\n\n0.1.2-alpha.3 已移除可选 SQLite Session 后端；使用自定义 SQLite Profile 时应先在旧版导出。"
        alert.addButton(withTitle: "启用 Alpha 通道")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.setHarnessUpdateChannel(.alpha)
        }
    }

    private func setHarnessUpdateChannel(_ channel: HarnessUpdateChannel) {
        harnessUpdateChannel = channel
        UserDefaults.standard.set(channel.rawValue, forKey: harnessUpdateChannelDefaultsKey)
        refreshHarnessVersionMenuItems()
    }

    @objc private func checkForHarnessUpdate(_ sender: Any?) {
        guard !isCheckingForHarnessUpdate else { return }
        isCheckingForHarnessUpdate = true
        refreshHarnessVersionMenuItems()
        let requestedChannel = harnessUpdateChannel

        var request = URLRequest(url: harnessDistTagsURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DeepSeek-Harness-macOS-Launcher", forHTTPHeaderField: "User-Agent")

        updateSession.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<[String: String], Error>
            if let error {
                result = .failure(error)
            } else if let httpResponse = response as? HTTPURLResponse,
                      !(200...299).contains(httpResponse.statusCode) {
                result = .failure(HarnessUpdateError.httpStatus(httpResponse.statusCode))
            } else if response as? HTTPURLResponse == nil {
                result = .failure(HarnessUpdateError.invalidResponse)
            } else if let data,
                      let distTags = try? JSONDecoder().decode([String: String].self, from: data) {
                result = .success(distTags)
            } else {
                result = .failure(HarnessUpdateError.invalidMetadata)
            }

            DispatchQueue.main.async {
                self?.finishHarnessUpdateCheck(result, channel: requestedChannel)
            }
        }.resume()
    }

    private func finishHarnessUpdateCheck(
        _ result: Result<[String: String], Error>,
        channel: HarnessUpdateChannel
    ) {
        isCheckingForHarnessUpdate = false
        refreshHarnessVersionMenuItems()

        switch result {
        case let .failure(error):
            presentAlert(
                title: "无法检查 Harness 更新",
                detail: "没有更改当前内核。\n\n\(error.localizedDescription)",
                style: .warning
            )
        case let .success(distTags):
            guard let newestVersion = newestOfficialHarnessVersion(in: distTags, channel: channel),
                  let newestSemanticVersion = SemanticVersion(newestVersion),
                  let selectedSemanticVersion = SemanticVersion(selectedHarnessPackageVersion) else {
                presentAlert(
                    title: "无法识别官方版本",
                    detail: "npm 官方版本信息中没有可用于\(channel.displayName)通道的合法版本。",
                    style: .warning
                )
                return
            }

            guard selectedSemanticVersion < newestSemanticVersion else {
                presentAlert(
                    title: "Harness 内核已是最新",
                    detail: "当前选择：\(selectedHarnessPackageVersion)\n\(channel.displayName)通道最新：\(newestVersion)",
                    style: .informational
                )
                return
            }

            let alert = NSAlert()
            alert.alertStyle = channel == .alpha ? .warning : .informational
            alert.messageText = channel == .alpha
                ? "发现官方 Harness Alpha 更新"
                : "发现官方 Harness 内核更新"
            var detail = "当前：\(selectedHarnessPackageVersion)\n新版：\(newestVersion)\n更新通道：\(channel.displayName)"
            detail += "\n\n继续后将从 npm 官方注册表获取新版。Harness 仍处于 Developer Preview，新版可能包含不兼容变化；可以从 App 菜单回退到上一版 \(selectedHarnessPackageVersion)。"
            if channel == .alpha {
                detail += "\n\n注意：版本回退不会自动逆转新版内核已经写入的数据格式变化。"
            }
            alert.informativeText = detail
            alert.addButton(withTitle: "更新并重启")
            alert.addButton(withTitle: "取消")
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.selectHarnessPackageVersion(newestVersion)
            }
        }
    }

    @objc private func rollBackToPreviousHarnessVersion(_ sender: Any?) {
        guard !isCheckingForHarnessUpdate,
              let previousVersion = previousHarnessPackageVersion,
              SemanticVersion(previousVersion) != nil else { return }

        let remainingSteps = harnessPackageVersionHistory.count - 1
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "回退到上一版 Harness 内核？"
        var detail = "当前：\(selectedHarnessPackageVersion)\n回退为：\(previousVersion)"
        if remainingSteps > 0 {
            detail += "\n\n回退后还可以继续向前回退 \(remainingSteps) 步。"
        }
        alert.informativeText = detail
        alert.addButton(withTitle: "回退并重启")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.applyPreviousHarnessPackageVersion(previousVersion)
        }
    }

    private func applyPreviousHarnessPackageVersion(_ version: String) {
        // The sheet is asynchronous, so make sure the history did not move on meanwhile.
        guard harnessPackageVersionHistory.last == version else {
            refreshHarnessVersionMenuItems()
            return
        }

        harnessPackageVersionHistory.removeLast()
        persistHarnessPackageVersionHistory()
        selectHarnessPackageVersion(version, recordingHistory: false)
    }

    private func selectHarnessPackageVersion(_ version: String, recordingHistory: Bool = true) {
        guard SemanticVersion(version) != nil else {
            presentAlert(title: "版本无效", detail: "没有更改当前 Harness 内核。", style: .warning)
            return
        }
        guard version != selectedHarnessPackageVersion else { return }

        let previousVersion = selectedHarnessPackageVersion
        if recordingHistory {
            recordHarnessPackageVersionInHistory(previousVersion)
        }

        pendingHarnessSwitchFromVersion = previousVersion
        isAutomaticHarnessRollback = false
        selectedHarnessPackageVersion = version
        UserDefaults.standard.set(version, forKey: harnessVersionDefaultsKey)
        UserDefaults.standard.set(true, forKey: packageApprovalDefaultsKey)
        refreshHarnessVersionMenuItems()
        restartHarnessForSelectedVersion()
    }

    private func restartHarnessForSelectedVersion() {
        probeTimer?.invalidate()
        probeTimer = nil
        probeAttempts = 0

        if harnessWasStartedByThisApp, let process = harnessProcess, process.isRunning {
            isHarnessTransitionInProgress = true
            restartHarnessAfterTermination = true
            harnessPageHasLoaded = false
            webView.stopLoading()
            showStartup(
                status: "正在切换 Harness 内核",
                detail: "已选择 \(harnessPackageSpecifier)，正在重启本机服务…",
                isError: false
            )
            appendLog("Switching Harness package to \(harnessPackageSpecifier).\n")
            process.terminate()
            return
        }

        probeHarness { [weak self] result in
            guard let self else { return }
            if result != .unavailable {
                // The external service keeps running unchanged. Reconstruct any
                // future switch from the persisted last-known-good version when
                // this App eventually owns the next launch.
                self.pendingHarnessSwitchFromVersion = nil
                self.isHarnessTransitionInProgress = false
                self.presentAlert(
                    title: "新版内核已选择",
                    detail: "下次由此 App 启动 Harness 时，将使用 \(self.harnessPackageSpecifier)。\n\n当前 127.0.0.1:3080 服务不是由此 App 启动，因此没有擅自终止它。",
                    style: .informational
                )
            } else {
                self.harnessPageHasLoaded = false
                self.webView.stopLoading()
                self.showStartup(
                    status: "正在启动更新后的 Harness",
                    detail: "正在运行 \(self.harnessPackageSpecifier)…",
                    isError: false
                )
                self.startHarnessProcess()
            }
        }
    }

    private func resolveSelectedHarnessPackageVersion() -> String {
        guard let minimumVersion = SemanticVersion(minimumRollbackHarnessPackageVersion),
              let storedValue = UserDefaults.standard.string(forKey: harnessVersionDefaultsKey),
              let storedVersion = SemanticVersion(storedValue),
              minimumVersion <= storedVersion else {
            return defaultHarnessPackageVersion
        }
        return storedValue
    }

    private func resolveHarnessUpdateChannel() -> HarnessUpdateChannel {
        guard let rawValue = UserDefaults.standard.string(forKey: harnessUpdateChannelDefaultsKey),
              let channel = HarnessUpdateChannel(rawValue: rawValue) else {
            return .defaultRelease
        }
        return channel
    }

    private func resolveLastKnownGoodHarnessPackageVersion() -> String {
        guard let minimumVersion = SemanticVersion(minimumRollbackHarnessPackageVersion),
              let storedValue = UserDefaults.standard.string(forKey: lastKnownGoodHarnessVersionDefaultsKey),
              let storedVersion = SemanticVersion(storedValue),
              minimumVersion <= storedVersion else {
            if selectedHarnessPackageVersion == verifiedFallbackHarnessPackageVersion {
                return selectedHarnessPackageVersion
            }
            return verifiedFallbackHarnessPackageVersion
        }
        return storedValue
    }

    private func recordHarnessPackageVersionInHistory(_ version: String) {
        guard SemanticVersion(version) != nil else { return }

        harnessPackageVersionHistory.removeAll { $0 == version }
        harnessPackageVersionHistory.append(version)
        if harnessPackageVersionHistory.count > harnessVersionHistoryLimit {
            harnessPackageVersionHistory.removeFirst(harnessPackageVersionHistory.count - harnessVersionHistoryLimit)
        }
        persistHarnessPackageVersionHistory()
    }

    private func persistHarnessPackageVersionHistory() {
        UserDefaults.standard.set(harnessPackageVersionHistory, forKey: harnessVersionHistoryDefaultsKey)
    }

    private func resolveHarnessPackageVersionHistory() -> [String] {
        guard let minimumVersion = SemanticVersion(minimumRollbackHarnessPackageVersion),
              let storedValues = UserDefaults.standard.array(forKey: harnessVersionHistoryDefaultsKey) as? [String] else {
            return []
        }

        var history: [String] = []
        for value in storedValues {
            guard let version = SemanticVersion(value),
                  minimumVersion <= version,
                  value != selectedHarnessPackageVersion else { continue }
            history.removeAll { $0 == value }
            history.append(value)
        }

        return Array(history.suffix(harnessVersionHistoryLimit))
    }

    private func markOwnedHarnessReady() {
        guard harnessWasStartedByThisApp,
              let process = harnessProcess,
              process.isRunning,
              activeOwnedHarnessVersion == selectedHarnessPackageVersion else { return }
        lastKnownGoodHarnessPackageVersion = selectedHarnessPackageVersion
        UserDefaults.standard.set(selectedHarnessPackageVersion, forKey: lastKnownGoodHarnessVersionDefaultsKey)
        pendingHarnessSwitchFromVersion = nil
        isAutomaticHarnessRollback = false
        isHarnessTransitionInProgress = false
        refreshHarnessVersionMenuItems()
    }

    private func recoverFromHarnessStartupFailure(_ reason: String) -> Bool {
        guard !isAutomaticHarnessRollback,
              let previousVersion = pendingHarnessSwitchFromVersion,
              previousVersion != selectedHarnessPackageVersion,
              SemanticVersion(previousVersion) != nil else { return false }

        let failedVersion = selectedHarnessPackageVersion
        isAutomaticHarnessRollback = true
        isHarnessTransitionInProgress = true
        pendingHarnessSwitchFromVersion = nil
        harnessPackageVersionHistory.removeAll { $0 == previousVersion }
        persistHarnessPackageVersionHistory()
        selectedHarnessPackageVersion = previousVersion
        UserDefaults.standard.set(previousVersion, forKey: harnessVersionDefaultsKey)
        appendLog("Harness \(failedVersion) did not become ready; automatically restoring \(previousVersion). Reason: \(reason)\n")
        refreshHarnessVersionMenuItems()

        showStartup(
            status: "新版启动失败，正在自动回退",
            detail: "\(failedVersion) 未通过就绪验证。正在恢复 \(previousVersion)…",
            isError: false
        )

        if let process = harnessProcess, process.isRunning {
            restartHarnessAfterTermination = true
            harnessPageHasLoaded = false
            webView.stopLoading()
            process.terminate()
            return true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.startHarnessProcess()
        }
        return true
    }

    private func presentAlert(title: String, detail: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }

    // MARK: - Archived session cleanup

    private var harnessHomeURL: URL {
        resolveHarnessHomeURL()
    }

    private var harnessSessionsRootURL: URL {
        harnessHomeURL.appendingPathComponent(harnessSessionsDirectoryName, isDirectory: true).standardizedFileURL
    }

    private var workspaceRegistryURL: URL {
        harnessHomeURL
            .appendingPathComponent(harnessStoragesDirectoryName, isDirectory: true)
            .appendingPathComponent(harnessWorkspaceRegistryFileName, isDirectory: false)
    }

    private var legacySessionCacheURL: URL {
        harnessHomeURL
            .appendingPathComponent(harnessStoragesDirectoryName, isDirectory: true)
            .appendingPathComponent(legacyHarnessSessionCacheFileName, isDirectory: false)
    }

    private var sessionProjectionCacheRecordsRootURL: URL {
        harnessHomeURL
            .appendingPathComponent(harnessStoragesDirectoryName, isDirectory: true)
            .appendingPathComponent(harnessSessionCacheDirectoryName, isDirectory: true)
            .appendingPathComponent(harnessSessionCacheRecordsDirectoryName, isDirectory: true)
            .standardizedFileURL
    }

    private func purgeArchivedSessionsMenuItemTitle(count: Int) -> String {
        count > 0 ? "清除已归档的会话…（\(count) 个）" : "清除已归档的会话…"
    }

    private func isSafeRegularStorageFile(_ url: URL) -> Bool {
        isRegularFileWithoutSymlinks(url)
    }

    private func loadHarnessStorage(at url: URL) -> [String: Any]? {
        guard isSafeRegularStorageFile(url),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private func writeHarnessStorage(_ storage: [String: Any], to url: URL) throws {
        guard isSafeRegularStorageFile(url) else { throw CocoaError(.fileWriteInvalidFileName) }
        let data = try JSONSerialization.data(withJSONObject: storage)
        try data.write(to: url, options: .atomic)
    }

    private func directoryByteSize(of url: URL) -> Int64 {
        // Hidden files count: the whole directory is what moves to the Trash.
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    private func fileByteSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey]),
              values.isRegularFile == true else { return 0 }
        return Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    /// Finds the transcript directories of the given sessions by scanning the project
    /// directories under the sessions root. The kernel escapes session ids into path
    /// segments, so matching what is on disk is safer than re-deriving the encoding here:
    /// an id whose directory is not found simply keeps its files and loses no data.
    private func locateSessionDirectories(ids: Set<String>) -> [URL] {
        let root = harnessSessionsRootURL
        guard let projectDirectories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var located: [URL] = []
        for projectDirectory in projectDirectories {
            guard let projectValues = try? projectDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  projectValues.isDirectory == true,
                  projectValues.isSymbolicLink != true,
                  let sessionDirectories = try? FileManager.default.contentsOfDirectory(
                      at: projectDirectory,
                      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                      options: [.skipsHiddenFiles]
                  ) else { continue }

            for sessionDirectory in sessionDirectories {
                guard ids.contains(sessionDirectory.lastPathComponent),
                      let sessionValues = try? sessionDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      sessionValues.isDirectory == true,
                      sessionValues.isSymbolicLink != true else { continue }
                located.append(sessionDirectory.standardizedFileURL)
            }
        }
        return located.sorted { $0.path < $1.path }
    }

    /// Guards every removal: only `<harness home>/sessions/<project>/<session>` may be trashed.
    private func isRemovableSessionDirectory(_ url: URL) -> Bool {
        let sessionDirectory = url.standardizedFileURL
        let projectDirectory = sessionDirectory.deletingLastPathComponent()
        guard let sessionValues = try? sessionDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              let projectValues = try? projectDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return sessionValues.isDirectory == true
            && sessionValues.isSymbolicLink != true
            && projectValues.isDirectory == true
            && projectValues.isSymbolicLink != true
            && projectDirectory.deletingLastPathComponent().path == harnessSessionsRootURL.path
            && !sessionDirectory.lastPathComponent.isEmpty
            && !projectDirectory.lastPathComponent.isEmpty
    }

    /// Finds only direct, regular, non-symlink v4 projection-cache records whose
    /// filename stem exactly matches an archived session id. Session ids are never
    /// interpolated into a deletion path.
    private func locateProjectionCacheRecords(ids: Set<String>) -> ProjectionCacheRecordScan {
        scanProjectionCacheRecords(in: sessionProjectionCacheRecordsRootURL, matching: ids)
    }

    private func isRemovableProjectionCacheRecord(_ url: URL) -> Bool {
        let record = url.standardizedFileURL
        guard record.deletingLastPathComponent().path == sessionProjectionCacheRecordsRootURL.path,
              record.pathExtension == "json",
              !record.deletingPathExtension().lastPathComponent.isEmpty,
              let values = try? record.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
            && projectionCacheRecordIsVersion4(record)
    }

    private func moveCleanupItemToTrash(_ url: URL, byteSize: Int64) throws -> TrashedPathMove {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        guard let trashURL = resultingURL as URL? else {
            throw CocoaError(.fileWriteUnknown)
        }
        return TrashedPathMove(
            originalURL: url.standardizedFileURL,
            trashURL: trashURL.standardizedFileURL,
            byteSize: byteSize
        )
    }

    private func restoreTrashedCleanupItems(
        _ moves: [TrashedPathMove]
    ) -> (restoredCount: Int, restoredBytes: Int64, failures: [String]) {
        var restoredCount = 0
        var restoredBytes: Int64 = 0
        var failures: [String] = []

        for move in moves.reversed() {
            let originalParent = move.originalURL.deletingLastPathComponent().standardizedFileURL
            guard !FileManager.default.fileExists(atPath: move.originalURL.path),
                  originalParent.resolvingSymlinksInPath().path == originalParent.path,
                  let parentValues = try? originalParent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  parentValues.isDirectory == true,
                  parentValues.isSymbolicLink != true,
                  FileManager.default.fileExists(atPath: move.trashURL.path) else {
                failures.append("\(move.originalURL.lastPathComponent)：无法验证回滚路径")
                continue
            }

            do {
                try FileManager.default.moveItem(at: move.trashURL, to: move.originalURL)
                restoredCount += 1
                restoredBytes += move.byteSize
            } catch {
                failures.append("\(move.originalURL.lastPathComponent)：回滚失败：\(error.localizedDescription)")
            }
        }
        return (restoredCount, restoredBytes, failures)
    }

    private func makeArchivedSessionCleanupPlan() -> ArchivedSessionCleanupPlan {
        let sessionIds = archivedSessionIds(in: loadHarnessStorage(at: workspaceRegistryURL) ?? [:])
        return makeArchivedSessionCleanupPlan(sessionIds: sessionIds)
    }

    /// Re-scan at the execution boundary. Alpha.3 writes a mandatory projection
    /// checkpoint while sessions are disposed, so stopping the kernel can create a
    /// cache record or transcript after the confirmation sheet was shown.
    private func makeArchivedSessionCleanupPlan(sessionIds: [String]) -> ArchivedSessionCleanupPlan {
        guard !sessionIds.isEmpty else { return .empty }

        let idSet = Set(sessionIds)
        let directories = locateSessionDirectories(ids: idSet)
        let projectionCacheScan = locateProjectionCacheRecords(ids: idSet)
        let byteSize = directories.reduce(Int64(0)) { $0 + directoryByteSize(of: $1) }
            + projectionCacheScan.records.reduce(Int64(0)) { $0 + fileByteSize(of: $1) }
        return ArchivedSessionCleanupPlan(
            sessionIds: sessionIds,
            directories: directories,
            projectionCacheRecords: projectionCacheScan.records,
            validationFailures: projectionCacheScan.failures,
            byteSize: byteSize
        )
    }

    private func formattedByteSize(_ byteSize: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    @objc private func purgeArchivedSessions(_ sender: Any?) {
        let plan = makeArchivedSessionCleanupPlan()
        guard !plan.isEmpty else {
            presentAlert(
                title: "没有已归档的会话",
                detail: "先在工作台的会话列表里归档不再需要的对话，然后再回到这里清除它们的记录。",
                style: .informational
            )
            return
        }
        guard plan.isValid else {
            presentAlert(
                title: "无法安全清除归档会话",
                detail: "发现当前启动器不支持或不安全的投影缓存格式，因此没有移动或改写任何记录：\n\n" + plan.validationFailures.joined(separator: "\n"),
                style: .warning
            )
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "清除 \(plan.sessionIds.count) 个已归档的会话？"
        var detail = "官方 Harness 只把归档的会话从列表中隐藏，完整记录仍保存在 \(harnessHomeURL.path)。"
        if plan.directories.isEmpty {
            detail += "\n\n这些会话没有留下记录文件，只需清理列表中的残留条目。"
        } else {
            detail += "\n\n将有 \(plan.directories.count) 份会话记录（共 \(formattedByteSize(plan.byteSize))）移入废纸篓，可以从废纸篓恢复。"
        }
        if !plan.projectionCacheRecords.isEmpty {
            detail += "\n同时清理 \(plan.projectionCacheRecords.count) 份 alpha.3 逐会话投影缓存。"
        }
        detail += "\n\n内核会把会话列表常驻内存并回写，因此清除时会先停止再重启 Harness 内核；工作台里未发送的内容可能丢失。"
        alert.informativeText = detail
        alert.addButton(withTitle: "移入废纸篓并重启")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.startArchivedSessionCleanup(plan)
        }
    }

    private func startArchivedSessionCleanup(_ plan: ArchivedSessionCleanupPlan) {
        if harnessWasStartedByThisApp, let process = harnessProcess, process.isRunning {
            isHarnessTransitionInProgress = true
            probeTimer?.invalidate()
            probeTimer = nil
            probeAttempts = 0
            pendingArchivedSessionCleanup = plan
            restartHarnessAfterTermination = true
            harnessPageHasLoaded = false
            webView.stopLoading()
            showStartup(
                status: "正在清除已归档的会话",
                detail: "正在停止本机服务，随后移除 \(plan.sessionIds.count) 个会话的记录…",
                isError: false
            )
            appendLog("Stopping Harness to remove \(plan.sessionIds.count) archived session(s).\n")
            process.terminate()
            return
        }

        probeHarness { [weak self] result in
            guard let self else { return }
            if result != .unavailable {
                self.presentAlert(
                    title: "请先停止外部 Harness 服务",
                    detail: "当前 127.0.0.1:3080 的服务不是由此 App 启动，因此没有擅自终止它。内核会把会话列表常驻内存并回写，运行中删除会被它覆盖。请先停止那个服务，再重新执行清除。",
                    style: .warning
                )
                return
            }

            let refreshedPlan = self.makeArchivedSessionCleanupPlan(sessionIds: plan.sessionIds)
            self.isHarnessTransitionInProgress = true
            let outcome = self.removeArchivedSessions(refreshedPlan)
            self.isHarnessTransitionInProgress = false
            self.presentCleanupOutcome(outcome)
        }
    }

    /// Removes the planned sessions from disk and from both storage files. Only sessions
    /// whose transcript is gone lose their registry entries, so a directory that could not
    /// be trashed stays visible in the workspace instead of becoming an orphaned file.
    private func removeArchivedSessions(_ plan: ArchivedSessionCleanupPlan) -> ArchivedSessionCleanupOutcome {
        var outcome = ArchivedSessionCleanupOutcome()

        guard plan.isValid else {
            outcome.failures.append(contentsOf: plan.validationFailures.map { "\($0)：未执行任何清除。" })
            return outcome
        }

        guard let registry = loadHarnessStorage(at: workspaceRegistryURL),
              storageUnit(registry, matchesName: "workspace", version: 2) else {
            outcome.failures.append("workspace.json：文件不是安全的普通文件，或格式不是受支持的 workspace v2；未执行任何清除。")
            return outcome
        }

        let legacyCacheExists = FileManager.default.fileExists(atPath: legacySessionCacheURL.path)
        let legacyCache = legacyCacheExists ? loadHarnessStorage(at: legacySessionCacheURL) : nil
        if legacyCacheExists,
           (legacyCache == nil || !storageUnit(legacyCache!, matchesName: "session_projcache", version: 3)) {
            outcome.failures.append("\(legacyHarnessSessionCacheFileName)：文件不是安全的普通文件，或格式不是受支持的 session_projcache v3；未执行任何清除。")
            return outcome
        }

        guard let backupDirectory = backUpHarnessStorages(
            projectionCacheRecords: plan.projectionCacheRecords
        ) else {
            outcome.failures.append("无法创建改动前备份，未执行任何清除。")
            return outcome
        }
        outcome.backupDirectory = backupDirectory

        var removedIds = Set(plan.sessionIds)
        var trashedTranscripts: [TrashedPathMove] = []
        for directory in plan.directories {
            let sessionId = directory.lastPathComponent
            guard isRemovableSessionDirectory(directory) else {
                removedIds.remove(sessionId)
                outcome.failures.append("\(sessionId)：不在 \(harnessSessionsRootURL.path) 之内，已跳过。")
                continue
            }

            let byteSize = directoryByteSize(of: directory)
            do {
                let move = try moveCleanupItemToTrash(directory, byteSize: byteSize)
                trashedTranscripts.append(move)
                outcome.trashedDirectories += 1
                outcome.freedBytes += byteSize
            } catch {
                removedIds.remove(sessionId)
                outcome.failures.append("\(sessionId)：\(error.localizedDescription)")
            }
        }

        guard !removedIds.isEmpty else { return outcome }

        do {
            try writeHarnessStorage(workspaceRegistry(registry, removingSessionIds: removedIds), to: workspaceRegistryURL)
            outcome.removedRegistryEntries = removedIds.count
        } catch {
            outcome.failures.append("\(harnessWorkspaceRegistryFileName)：\(error.localizedDescription)")
            let restore = restoreTrashedCleanupItems(trashedTranscripts)
            outcome.trashedDirectories -= restore.restoredCount
            outcome.freedBytes -= restore.restoredBytes
            outcome.failures.append(contentsOf: restore.failures)
            return outcome
        }

        if let legacyCache {
            do {
                try writeHarnessStorage(
                    sessionProjectionCache(legacyCache, removingSessionIds: removedIds),
                    to: legacySessionCacheURL
                )
            } catch {
                outcome.failures.append("\(legacyHarnessSessionCacheFileName)：\(error.localizedDescription)")
                let restore = restoreTrashedCleanupItems(trashedTranscripts)
                outcome.trashedDirectories -= restore.restoredCount
                outcome.freedBytes -= restore.restoredBytes
                outcome.failures.append(contentsOf: restore.failures)
                if restore.restoredCount == trashedTranscripts.count {
                    do {
                        try writeHarnessStorage(registry, to: workspaceRegistryURL)
                        try writeHarnessStorage(legacyCache, to: legacySessionCacheURL)
                        outcome.removedRegistryEntries = 0
                    } catch {
                        outcome.failures.append("workspace.json：自动恢复失败：\(error.localizedDescription)")
                    }
                } else {
                    outcome.failures.append("部分 transcript 未能恢复，因此没有自动恢复 workspace.json；请使用备份人工处理。")
                }
                return outcome
            }
        }

        var trashedProjectionRecords: [TrashedPathMove] = []
        for record in plan.projectionCacheRecords {
            let sessionId = record.deletingPathExtension().lastPathComponent
            guard removedIds.contains(sessionId) else { continue }
            guard isRemovableProjectionCacheRecord(record) else {
                outcome.failures.append("\(record.lastPathComponent)：投影缓存路径或 v4 格式在执行前发生变化，开始自动回滚。")
                let projectionRestore = restoreTrashedCleanupItems(trashedProjectionRecords)
                let transcriptRestore = restoreTrashedCleanupItems(trashedTranscripts)
                outcome.removedProjectionCacheRecords -= projectionRestore.restoredCount
                outcome.trashedDirectories -= transcriptRestore.restoredCount
                outcome.freedBytes -= projectionRestore.restoredBytes + transcriptRestore.restoredBytes
                outcome.failures.append(contentsOf: projectionRestore.failures + transcriptRestore.failures)
                if projectionRestore.restoredCount == trashedProjectionRecords.count,
                   transcriptRestore.restoredCount == trashedTranscripts.count {
                    do {
                        try writeHarnessStorage(registry, to: workspaceRegistryURL)
                        if let legacyCache { try writeHarnessStorage(legacyCache, to: legacySessionCacheURL) }
                        outcome.removedRegistryEntries = 0
                    } catch {
                        outcome.failures.append("存储索引自动恢复失败：\(error.localizedDescription)")
                    }
                } else {
                    outcome.failures.append("部分文件未能恢复，因此没有自动恢复存储索引；请使用备份人工处理。")
                }
                return outcome
            }

            do {
                let byteSize = fileByteSize(of: record)
                let move = try moveCleanupItemToTrash(record, byteSize: byteSize)
                trashedProjectionRecords.append(move)
                outcome.removedProjectionCacheRecords += 1
                outcome.freedBytes += byteSize
            } catch {
                outcome.failures.append("\(record.lastPathComponent)：\(error.localizedDescription)，开始自动回滚。")
                let projectionRestore = restoreTrashedCleanupItems(trashedProjectionRecords)
                let transcriptRestore = restoreTrashedCleanupItems(trashedTranscripts)
                outcome.removedProjectionCacheRecords -= projectionRestore.restoredCount
                outcome.trashedDirectories -= transcriptRestore.restoredCount
                outcome.freedBytes -= projectionRestore.restoredBytes + transcriptRestore.restoredBytes
                outcome.failures.append(contentsOf: projectionRestore.failures + transcriptRestore.failures)
                if projectionRestore.restoredCount == trashedProjectionRecords.count,
                   transcriptRestore.restoredCount == trashedTranscripts.count {
                    do {
                        try writeHarnessStorage(registry, to: workspaceRegistryURL)
                        if let legacyCache { try writeHarnessStorage(legacyCache, to: legacySessionCacheURL) }
                        outcome.removedRegistryEntries = 0
                    } catch {
                        outcome.failures.append("存储索引自动恢复失败：\(error.localizedDescription)")
                    }
                } else {
                    outcome.failures.append("部分文件未能恢复，因此没有自动恢复存储索引；请使用备份人工处理。")
                }
                return outcome
            }
        }

        return outcome
    }

    /// Copies both storage files aside before they are rewritten, keeping the most recent
    /// few. They are small, and a bad rewrite would otherwise cost the whole session list.
    private func backUpHarnessStorages(projectionCacheRecords: [URL]) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"

        let logDirectory = logURL.deletingLastPathComponent().standardizedFileURL
        guard ensureRealDirectory(logDirectory) else { return nil }

        let backupRoot = logDirectory.appendingPathComponent("storage-backups", isDirectory: true).standardizedFileURL
        guard backupRoot.deletingLastPathComponent().path == logDirectory.path,
              ensureRealDirectory(backupRoot) else { return nil }
        let backupDirectory = backupRoot.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)

        do {
            guard !FileManager.default.fileExists(atPath: backupDirectory.path),
                  backupDirectory.deletingLastPathComponent().path == backupRoot.path else { return nil }
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: false)
            guard ensureRealDirectory(backupDirectory) else { return nil }
            for source in [workspaceRegistryURL, legacySessionCacheURL] {
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                guard isSafeRegularStorageFile(source) else { throw CocoaError(.fileReadInvalidFileName) }
                let destination = backupDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: false)
                try FileManager.default.copyItem(at: source, to: destination)
            }

            if !projectionCacheRecords.isEmpty {
                let recordsBackupDirectory = backupDirectory
                    .appendingPathComponent(harnessSessionCacheDirectoryName, isDirectory: true)
                    .appendingPathComponent(harnessSessionCacheRecordsDirectoryName, isDirectory: true)
                try FileManager.default.createDirectory(at: recordsBackupDirectory, withIntermediateDirectories: true)
                for source in projectionCacheRecords {
                    guard isRemovableProjectionCacheRecord(source) else { throw CocoaError(.fileReadInvalidFileName) }
                    try FileManager.default.copyItem(
                        at: source,
                        to: recordsBackupDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: false)
                    )
                }
            }
        } catch {
            return nil
        }

        pruneHarnessStorageBackups(in: backupRoot)
        return backupDirectory
    }

    private func ensureRealDirectory(_ url: URL) -> Bool {
        let directory = url.standardizedFileURL
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }
        guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func pruneHarnessStorageBackups(in backupRoot: URL) {
        guard let backups = try? FileManager.default.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = backups
            .filter { candidate in
                guard candidate.standardizedFileURL.deletingLastPathComponent().path == backupRoot.standardizedFileURL.path,
                      let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
                    return false
                }
                return values.isDirectory == true && values.isSymbolicLink != true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard sorted.count > harnessStorageBackupLimit else { return }

        for obsolete in sorted.prefix(sorted.count - harnessStorageBackupLimit) {
            try? FileManager.default.trashItem(at: obsolete, resultingItemURL: nil)
        }
    }

    private func cleanupLogLine(for outcome: ArchivedSessionCleanupOutcome) -> String {
        var line = "Archived session cleanup: trashed \(outcome.trashedDirectories) transcript(s), "
        line += "removed \(outcome.removedProjectionCacheRecords) projection cache record(s), "
        line += "freed \(outcome.freedBytes) bytes, removed \(outcome.removedRegistryEntries) registry entr(y/ies)."
        if !outcome.failures.isEmpty {
            line += " Failures: \(outcome.failures.joined(separator: "; "))"
        }
        return line + "\n"
    }

    private func presentCleanupOutcome(_ outcome: ArchivedSessionCleanupOutcome) {
        var detail = outcome.trashedDirectories > 0
            ? "已把 \(outcome.trashedDirectories) 份会话记录（共 \(formattedByteSize(outcome.freedBytes))）移入废纸篓，可以从废纸篓恢复。"
            : "没有需要移入废纸篓的记录文件。"
        if outcome.removedRegistryEntries > 0 {
            detail += "\n工作台列表中的 \(outcome.removedRegistryEntries) 个条目也已清除。"
        }
        if outcome.removedProjectionCacheRecords > 0 {
            detail += "\n已清理 \(outcome.removedProjectionCacheRecords) 份逐会话投影缓存。"
        }
        if let backupDirectory = outcome.backupDirectory {
            detail += "\n\n改动前的列表数据已备份到：\n\(backupDirectory.path)"
        }

        if outcome.failures.isEmpty {
            presentAlert(title: "已清除归档会话", detail: detail, style: .informational)
            return
        }

        detail += "\n\n以下项目没有完全处理：\n" + outcome.failures.joined(separator: "\n")
        presentAlert(title: "清除未完全完成", detail: detail, style: .warning)
    }

    @objc private func reloadPage(_ sender: Any?) {
        if harnessPageHasLoaded {
            webView.reload()
        } else {
            retryConnection(sender)
        }
    }

    @objc private func increasePageZoom(_ sender: Any?) {
        applyPageZoom(currentPageZoom + pageZoomStep)
    }

    @objc private func decreasePageZoom(_ sender: Any?) {
        applyPageZoom(currentPageZoom - pageZoomStep)
    }

    @objc private func resetPageZoom(_ sender: Any?) {
        applyPageZoom(1.0)
    }

    private func storedPageZoom() -> CGFloat {
        guard let storedValue = UserDefaults.standard.object(forKey: pageZoomDefaultsKey) as? NSNumber else {
            return 1.0
        }
        return normalizedPageZoom(CGFloat(storedValue.doubleValue))
    }

    private func normalizedPageZoom(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1.0 }
        let clamped = Swift.min(Swift.max(value, minimumPageZoom), maximumPageZoom)
        return (clamped / pageZoomStep).rounded() * pageZoomStep
    }

    private func applyPageZoom(_ requestedZoom: CGFloat, persist: Bool = true) {
        currentPageZoom = normalizedPageZoom(requestedZoom)
        webView.pageZoom = currentPageZoom
        statusLabel?.font = NSFont.systemFont(ofSize: 25 * currentPageZoom, weight: .semibold)
        detailLabel?.font = NSFont.systemFont(ofSize: 14 * currentPageZoom, weight: .regular)

        if persist {
            UserDefaults.standard.set(Double(currentPageZoom), forKey: pageZoomDefaultsKey)
        }
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
        probeHarness { [weak self] result in
            guard let self else { return }
            if result == .ready {
                self.loadHarnessPage()
            } else if result == .authenticationRequired {
                // Let WKWebView use its own HttpOnly browser-session cookie if one
                // exists. We never enumerate or inspect browser storage; the
                // official final 200/401 response is the authority.
                self.loadHarnessPage()
            } else if result == .occupiedUnknown {
                self.showStartup(
                    status: "本机端口 3080 已被占用",
                    detail: "该服务未通过 DeepSeek Harness 身份检查。为避免连接或终止错误进程，App 没有继续启动。请先处理占用端口的服务，再点“重新尝试”。",
                    isError: true
                )
            } else if let process = self.harnessProcess, process.isRunning {
                self.showStartup(status: "正在启动 DeepSeek Harness", detail: "本机服务正在初始化…", isError: false)
                self.beginProbeLoop()
            } else {
                self.startHarnessProcess()
            }
        }
    }

    private func startHarnessProcess() {
        isHarnessTransitionInProgress = true
        if pendingHarnessSwitchFromVersion == nil,
           !isAutomaticHarnessRollback,
           selectedHarnessPackageVersion != lastKnownGoodHarnessPackageVersion {
            pendingHarnessSwitchFromVersion = lastKnownGoodHarnessPackageVersion
        }

        let discovery = discoverNodeRuntime()
        guard let runtime = discovery.runtime else {
            isHarnessTransitionInProgress = false
            showStartup(
                status: "需要兼容的 Node.js",
                detail: discovery.detail,
                isError: true
            )
            return
        }

        guard confirmOfficialPackageDownloadIfNeeded() else {
            isHarnessTransitionInProgress = false
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
            pendingHarnessAuthenticationURL = nil
            appendLog("\n--- Native app launch \(ISO8601DateFormatter().string(from: Date())) ---\n")
            appendLog("Harness package: \(harnessPackageSpecifier)\n")
            appendLog("Node: \(runtime.version) at \(runtime.nodeURL.path)\n")
            appendLog("Workspace: \(workspaceURL.path)\n")

            let process = Process()
            process.executableURL = runtime.npxURL
            // The native wrapper owns presentation. Prevent dsh from also opening the
            // same localhost UI in the user's default browser on every app launch.
            process.arguments = [
                "--yes", harnessPackageSpecifier, "web",
                "--host", "127.0.0.1", "--port", "3080", "--no-open"
            ]
            process.currentDirectoryURL = workspaceURL
            var environment = ProcessInfo.processInfo.environment
            let runtimeBin = runtime.nodeURL.deletingLastPathComponent().path
            let inheritedPath = environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(runtimeBin):\(inheritedPath)"
            process.environment = environment
            configureHarnessOutputCapture(for: process)
            process.terminationHandler = { [weak self] terminatedProcess in
                DispatchQueue.main.async {
                    guard let self, !self.isTerminating else { return }
                    self.harnessProcess = nil
                    self.harnessWasStartedByThisApp = false
                    self.activeOwnedHarnessVersion = nil
                    self.closeHarnessOutputCapture(afterProcessExit: true)
                    self.closeHarnessLogHandle()
                    self.pendingHarnessAuthenticationURL = nil
                    self.refreshHarnessVersionMenuItems()

                    if self.restartHarnessAfterTermination {
                        self.restartHarnessAfterTermination = false
                        let cleanup = self.pendingArchivedSessionCleanup
                        self.pendingArchivedSessionCleanup = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                            guard let self else { return }
                            // Re-scan after graceful disposal: alpha.3 may have written a final
                            // transcript or v4 projection checkpoint while it was stopping.
                            let outcome = cleanup.map {
                                self.removeArchivedSessions(
                                    self.makeArchivedSessionCleanupPlan(sessionIds: $0.sessionIds)
                                )
                            }
                            self.startHarnessProcess()
                            if let outcome {
                                self.appendLog(self.cleanupLogLine(for: outcome))
                                self.presentCleanupOutcome(outcome)
                            }
                        }
                        return
                    }

                    if self.recoverFromHarnessStartupFailure(
                        "process exited with code \(terminatedProcess.terminationStatus)"
                    ) {
                        return
                    }

                    self.probeHarness { result in
                        if result == .ready {
                            self.loadHarnessPage()
                        } else if !self.harnessPageHasLoaded {
                            self.isHarnessTransitionInProgress = false
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
            activeOwnedHarnessVersion = selectedHarnessPackageVersion
            refreshHarnessVersionMenuItems()
            showStartup(
                status: "正在启动 DeepSeek Harness",
                detail: "正在运行 \(harnessPackageSpecifier)\n工作区：\(workspaceURL.path)",
                isError: false
            )
            beginProbeLoop()
        } catch {
            closeHarnessOutputCapture()
            appendLog("Native launcher error: \(error.localizedDescription)\n")
            if !recoverFromHarnessStartupFailure(error.localizedDescription) {
                isHarnessTransitionInProgress = false
                showStartup(status: "无法启动 Harness", detail: error.localizedDescription, isError: true)
            }
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
        let isAlpha = selectedHarnessPackageVersion.contains("-alpha.")
        alert.alertStyle = isAlpha ? .warning : .informational
        alert.messageText = isAlpha ? "下载并启动官方 Harness Alpha？" : "下载并启动官方 DeepSeek Harness？"
        var detail = "此非官方启动器不内置 Harness。继续后，npx 将从 npm 获取并运行 \(harnessPackageSpecifier)。API Key 不会包含在 App 中，请稍后在 Harness 的 Settings → Models 中自行配置。"
        if isAlpha {
            detail += "\n\n这是 Developer Preview 实验版，可能写入新版数据格式。v3.0.0 会保留 0.1.1-rc.2 自动回退点，但版本回退不会逆转上游数据迁移。自定义 SQLite Session Profile 必须先在旧版导出。"
        }
        alert.informativeText = detail
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
        closeHarnessLogHandle()
        let directory = logURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        harnessLogHandle = handle
    }

    private func configureHarnessOutputCapture(for process: Process) {
        closeHarnessOutputCapture()
        guard let logHandle = harnessLogHandle else { return }
        let relay = HarnessProcessOutputRelay(logHandle: logHandle, expectedBaseURL: harnessBaseURL)
        harnessOutputRelay = relay
        relay.attach(to: process)
    }

    private func synchronizeHarnessAuthenticationURL() {
        if let authenticationURL = harnessOutputRelay?.authenticationURL() {
            pendingHarnessAuthenticationURL = authenticationURL
        }
    }

    private func closeHarnessOutputCapture(afterProcessExit: Bool = false) {
        guard let relay = harnessOutputRelay else { return }
        if afterProcessExit {
            relay.closeAfterProcessExit()
        } else {
            relay.invalidateWithoutDraining()
        }
        if let authenticationURL = relay.authenticationURL() {
            pendingHarnessAuthenticationURL = authenticationURL
        }
        harnessOutputRelay = nil
    }

    private func closeHarnessLogHandle() {
        try? harnessLogHandle?.synchronize()
        try? harnessLogHandle?.close()
        harnessLogHandle = nil
    }

    private func appendLog(_ message: String) {
        if let relay = harnessOutputRelay {
            relay.appendLog(message)
            return
        }
        let sanitized = redactedHarnessLogText(message)
        guard let data = sanitized.data(using: .utf8) else { return }
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
            if recoverFromHarnessStartupFailure("timed out waiting for authenticated HTTP readiness") {
                return
            }
            isHarnessTransitionInProgress = false
            showStartup(
                status: "Harness 尚未就绪",
                detail: "等待 90 秒后仍未收到 HTTP 200。请查看日志后重试。",
                isError: true
            )
            return
        }

        probeHarness { [weak self] result in
            guard let self else { return }
            self.synchronizeHarnessAuthenticationURL()
            if result == .ready || (result == .authenticationRequired && self.pendingHarnessAuthenticationURL != nil) {
                self.probeTimer?.invalidate()
                self.probeTimer = nil
                self.loadHarnessPage()
            }
        }
    }

    private func probeHarness(completion: @escaping (HarnessProbeResult) -> Void) {
        guard !probeInFlight else {
            completion(.unavailable)
            return
        }
        probeInFlight = true

        // Always probe the bare origin. The alpha.3 launch token must be handed to
        // WKWebView, not this cookie-less URLSession, so its HttpOnly cookie is retained.
        var components = URLComponents(url: harnessBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "_native_probe", value: String(Int(Date().timeIntervalSince1970 * 1_000)))
        ]

        var request = URLRequest(url: components?.url ?? harnessBaseURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 1.5
        request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        probeSession.dataTask(with: request) { [weak self] data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let pagePrefix = data.flatMap { String(data: $0.prefix(32_768), encoding: .utf8) }?.lowercased() ?? ""
            let identityIsReady = pagePrefix.contains("deepseek") || pagePrefix.contains("dsh-web")
            let result: HarnessProbeResult
            if statusCode == 200 && identityIsReady {
                result = .ready
            } else if statusCode == 401 && pagePrefix.contains("dsh web authentication required") {
                result = .authenticationRequired
            } else if statusCode != nil {
                result = .occupiedUnknown
            } else {
                result = .unavailable
            }
            DispatchQueue.main.async {
                self?.probeInFlight = false
                completion(result)
            }
        }.resume()
    }

    private func loadHarnessPage() {
        guard !harnessPageHasLoaded else { return }
        synchronizeHarnessAuthenticationURL()
        harnessPageHasLoaded = true
        validatedMainFrameHarnessResponse = false
        let targetURL = pendingHarnessAuthenticationURL ?? harnessBaseURL
        let detail = pendingHarnessAuthenticationURL == nil
            ? "本机服务已就绪（HTTP 200）"
            : "正在安全建立本机浏览器会话…"
        showStartup(status: "正在载入工作台", detail: detail, isError: false)
        var request = URLRequest(url: targetURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
    }


    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == nativeChromeMessageName, message.frameInfo.isMainFrame else { return }

        let host = message.frameInfo.securityOrigin.host.lowercased()
        guard host == "127.0.0.1" || host == "localhost" else { return }

        guard let payload = message.body as? [String: Any],
              let red = (payload["r"] as? NSNumber)?.doubleValue,
              let green = (payload["g"] as? NSNumber)?.doubleValue,
              let blue = (payload["b"] as? NSNumber)?.doubleValue else { return }

        applyChromeColor(red: red / 255, green: green / 255, blue: blue / 255)
    }

    /// Extends the page's own background into the title bar, the window frame and the system
    /// appearance, so the window reads as one surface instead of a page inside a frame.
    private func applyChromeColor(red: Double, green: Double, blue: Double) {
        let normalize: (Double) -> Double = { Swift.min(Swift.max($0, 0), 1) }
        let components = (red: normalize(red), green: normalize(green), blue: normalize(blue))
        let isUnchanged = abs(components.red - chromeComponents.red) < 0.004
            && abs(components.green - chromeComponents.green) < 0.004
            && abs(components.blue - chromeComponents.blue) < 0.004
        guard !isUnchanged else { return }

        chromeComponents = components
        chromeColor = NSColor(
            srgbRed: CGFloat(components.red),
            green: CGFloat(components.green),
            blue: CGFloat(components.blue),
            alpha: 1
        )
        chromeIsDark = prefersDarkChrome(
            red: components.red,
            green: components.green,
            blue: components.blue,
            currentlyDark: chromeIsDark
        )

        window.backgroundColor = chromeColor
        window.contentView?.layer?.backgroundColor = chromeColor.cgColor
        window.appearance = NSAppearance(named: chromeIsDark ? .darkAqua : .aqua)
        startupView?.layer?.backgroundColor = chromeColor.cgColor
        webView?.underPageBackgroundColor = chromeColor
        refreshStartupPalette()
    }

    private func refreshStartupPalette() {
        let primary = chromeIsDark ? NSColor.white : NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1)
        statusLabel?.textColor = primary
        detailLabel?.textColor = primary.withAlphaComponent(0.68)
    }

    private func revealWebContent() {
        guard !webView.isHidden || !startupView.isHidden else { return }

        if webView.isHidden {
            webView.alphaValue = 0
            webView.isHidden = false
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            webView.animator().alphaValue = 1
            startupView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.startupView.isHidden = true
            self.startupView.alphaValue = 1
            self.progressIndicator.stopAnimation(nil)
        })
    }

    private func showStartup(status: String, detail: String, isError: Bool) {
        startupView.alphaValue = 1
        startupView.isHidden = false
        webView.alphaValue = 1
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
        guard validatedMainFrameHarnessResponse,
              let finalURL = webView.url,
              isLocalHarnessURL(finalURL) else { return }
        window.title = appDisplayName
        pendingHarnessAuthenticationURL = nil
        markOwnedHarnessReady()
        refreshHarnessVersionMenuItems()
        revealWebContent()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        harnessPageHasLoaded = false
        validatedMainFrameHarnessResponse = false
        if !recoverFromHarnessStartupFailure(error.localizedDescription) {
            isHarnessTransitionInProgress = false
            showStartup(status: "页面载入失败", detail: error.localizedDescription, isError: true)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        harnessPageHasLoaded = false
        validatedMainFrameHarnessResponse = false
        if !recoverFromHarnessStartupFailure(error.localizedDescription) {
            isHarnessTransitionInProgress = false
            showStartup(status: "无法连接本机 Harness", detail: error.localizedDescription, isError: true)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame,
              let url = navigationResponse.response.url,
              isLocalHarnessURL(url),
              let response = navigationResponse.response as? HTTPURLResponse else {
            decisionHandler(.allow)
            return
        }

        if response.statusCode == 200 {
            validatedMainFrameHarnessResponse = true
            decisionHandler(.allow)
            return
        }

        if (300...399).contains(response.statusCode) {
            validatedMainFrameHarnessResponse = false
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)
        harnessPageHasLoaded = false
        validatedMainFrameHarnessResponse = false
        pendingHarnessAuthenticationURL = nil
        let reason = "local Harness page returned HTTP \(response.statusCode)"
        if !recoverFromHarnessStartupFailure(reason) {
            isHarnessTransitionInProgress = false
            showStartup(
                status: response.statusCode == 401 ? "Harness 需要访问令牌" : "Harness 页面响应异常",
                detail: response.statusCode == 401
                    ? "本机服务拒绝了当前浏览器会话。请停止外部 Harness 服务后重试，由此 App 重新建立安全会话。"
                    : reason,
                isError: true
            )
        }
        return
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

private func runSelfTests() -> Int32 {
    var failures: [String] = []

    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }

    expect(SemanticVersion("0.1.0-rc.6") != nil, "accept rc version")
    expect(SemanticVersion("0.1.0-rc.6;touch-bad") == nil, "reject unsafe package version")
    expect(SemanticVersion("0.1.0-rc.6")! < SemanticVersion("0.1.0-rc.7")!, "compare rc increments")
    expect(SemanticVersion("0.1.0-rc.9")! < SemanticVersion("0.1.0-rc.10")!, "compare numeric prerelease identifiers")
    expect(SemanticVersion("0.1.0-rc.6")! < SemanticVersion("0.1.0")!, "stable version follows prerelease")
    expect(SemanticVersion("0.1.0")! < SemanticVersion("0.2.0")!, "compare minor versions")
    expect(
        SemanticVersion("0.1.1-rc.2")! < SemanticVersion("0.1.2-alpha.3")!,
        "treat alpha.3 as newer than the current rc.2 line"
    )
    expect(
        newestOfficialHarnessVersion(
            in: ["latest": "0.1.0-rc.6", "next": "0.1.0-rc.7", "alpha": "0.1.2-alpha.3"],
            channel: .defaultRelease
        ) == "0.1.0-rc.7",
        "prefer newer official dist-tag"
    )
    expect(
        newestOfficialHarnessVersion(
            in: ["latest": "0.1.0", "next": "0.1.0-rc.9"],
            channel: .defaultRelease
        ) == "0.1.0",
        "prefer stable release over its prerelease"
    )
    expect(
        newestOfficialHarnessVersion(
            in: ["latest": "invalid", "next": "0.1.0-rc.6"],
            channel: .defaultRelease
        ) == "0.1.0-rc.6",
        "ignore invalid official metadata entries"
    )
    expect(
        newestOfficialHarnessVersion(
            in: ["latest": "0.1.1-rc.2", "next": "0.1.1-rc.2", "alpha": "0.1.2-alpha.3"],
            channel: .alpha
        ) == "0.1.2-alpha.3",
        "select the explicit alpha channel"
    )
    expect(
        newestOfficialHarnessVersion(
            in: ["latest": "0.1.2", "next": "0.1.1-rc.2", "alpha": "0.1.2-alpha.3"],
            channel: .alpha
        ) == "0.1.2",
        "let an alpha user graduate to a newer stable release"
    )

    let testToken = String(repeating: "A", count: 43)
    let outputInspection = inspectHarnessOutputLine(
        "dsh web: http://127.0.0.1:3080/?token=\(testToken)",
        expectedBaseURL: harnessBaseURL
    )
    expect(outputInspection.authenticationURL != nil, "capture the exact local alpha authentication URL")
    expect(!outputInspection.sanitizedLine.contains(testToken), "redact the alpha browser token from logs")
    expect(outputInspection.sanitizedLine.contains("<redacted>"), "leave an explicit token-redaction marker")
    expect(
        inspectHarnessOutputLine(
            "dsh web: https://example.com:3080/?token=\(testToken)",
            expectedBaseURL: harnessBaseURL
        ).authenticationURL == nil,
        "reject a non-local authentication URL"
    )
    expect(
        inspectHarnessOutputLine(
            "dsh web: http://127.0.0.1:3080/?token=short",
            expectedBaseURL: harnessBaseURL
        ).authenticationURL == nil,
        "reject a malformed alpha browser token"
    )
    expect(
        prefersDarkChrome(red: 0.018, green: 0.043, blue: 0.115, currentlyDark: false),
        "treat the Harness dark background as dark chrome"
    )
    expect(
        !prefersDarkChrome(red: 1, green: 1, blue: 1, currentlyDark: true),
        "treat a white page as light chrome"
    )
    expect(
        prefersDarkChrome(red: 0.5, green: 0.5, blue: 0.5, currentlyDark: true),
        "keep the current chrome inside the ambiguous luminance band"
    )


    let temporaryHome = URL(fileURLWithPath: "/tmp/harness-self-test-home", isDirectory: true)
    expect(
        resolveHarnessHomeURL(environment: [:], home: temporaryHome).path == "/tmp/harness-self-test-home/.dsh",
        "default the harness home to ~/.dsh"
    )
    expect(
        resolveHarnessHomeURL(environment: ["DSH_HOME": "   "], home: temporaryHome).path == "/tmp/harness-self-test-home/.dsh",
        "treat a blank DSH_HOME as unset"
    )
    expect(
        resolveHarnessHomeURL(environment: ["DSH_HOME": "~/harness-data"], home: temporaryHome).path
            == "/tmp/harness-self-test-home/harness-data",
        "expand a tilde in DSH_HOME"
    )
    expect(
        resolveHarnessHomeURL(environment: ["DSH_HOME": "/srv/dsh"], home: temporaryHome).path == "/srv/dsh",
        "honour an absolute DSH_HOME"
    )

    let registry: [String: Any] = [
        "unit": ["name": "workspace", "version": 2],
        "global": [
            "initialized": true,
            "workspaceIds": ["workspace-a"],
            "archivedSessionIds": ["session-1", "session-1", "session-2", 7]
        ],
        "tables": [
            "workspaces": [
                "workspace-a": [
                    "path": "/tmp/project",
                    "title": "project",
                    "sessionIds": ["session-1", "session-2", "session-3"]
                ]
            ]
        ]
    ]

    expect(storageUnit(registry, matchesName: "workspace", version: 2), "accept the official workspace v2 storage")
    expect(!storageUnit(registry, matchesName: "workspace", version: 3), "reject an unknown future workspace storage")

    expect(archivedSessionIds(in: registry) == ["session-1", "session-2"], "read archived ids without duplicates or non-strings")
    expect(archivedSessionIds(in: [:]).isEmpty, "tolerate a registry without an archive set")

    let prunedRegistry = workspaceRegistry(registry, removingSessionIds: ["session-1"])
    let prunedGlobal = prunedRegistry["global"] as? [String: Any]
    let prunedArchived = prunedGlobal?["archivedSessionIds"] as? [Any]
    let prunedWorkspaces = (prunedRegistry["tables"] as? [String: Any])?["workspaces"] as? [String: Any]
    let prunedWorkspace = prunedWorkspaces?["workspace-a"] as? [String: Any]
    expect(prunedArchived?.compactMap { $0 as? String } == ["session-2"], "drop the removed id from the archive set")
    expect(prunedArchived?.count == 2, "keep registry entries the launcher does not understand")
    expect(
        (prunedWorkspace?["sessionIds"] as? [Any])?.compactMap { $0 as? String } == ["session-2", "session-3"],
        "drop the removed id from its workspace"
    )
    expect(prunedWorkspace?["path"] as? String == "/tmp/project", "preserve unrelated workspace fields")
    expect((prunedRegistry["unit"] as? [String: Any])?["version"] as? Int == 2, "preserve the storage unit header")
    expect(
        (workspaceRegistry(registry, removingSessionIds: [])["global"] as? [String: Any])
            .flatMap { ($0["archivedSessionIds"] as? [Any])?.count } == 4,
        "leave the registry untouched when nothing is removed"
    )

    let cache: [String: Any] = [
        "unit": ["name": "session_projcache", "version": 3],
        "tables": ["sessions": ["session-1": ["rows": [:]], "session-2": ["rows": [:]]]]
    ]
    expect(storageUnit(cache, matchesName: "session_projcache", version: 3), "accept the legacy projection-cache v3 storage")
    let prunedCache = sessionProjectionCache(cache, removingSessionIds: ["session-1"])
    let prunedSessions = (prunedCache["tables"] as? [String: Any])?["sessions"] as? [String: Any]
    expect(prunedSessions?.count == 1 && prunedSessions?["session-2"] != nil, "drop only the removed session from the cache")
    expect(
        ((sessionProjectionCache([:], removingSessionIds: ["session-1"])) as NSDictionary).count == 0,
        "tolerate a cache without a sessions table"
    )

    let fixtureRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("deepseek-harness-projection-self-test-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let keptRecord = fixtureRoot.appendingPathComponent("session-1.json", isDirectory: false)
        let otherRecord = fixtureRoot.appendingPathComponent("session-2.json", isDirectory: false)
        let v4RecordData = Data(#"{"version":4,"record":{}}"#.utf8)
        try v4RecordData.write(to: keptRecord)
        try v4RecordData.write(to: otherRecord)
        try FileManager.default.createSymbolicLink(
            at: fixtureRoot.appendingPathComponent("session-link.json", isDirectory: false),
            withDestinationURL: keptRecord
        )
        let linkedRecord = fixtureRoot.appendingPathComponent("session-link.json", isDirectory: false)
        expect(isRegularFileWithoutSymlinks(keptRecord), "accept a direct regular storage file")
        expect(!isRegularFileWithoutSymlinks(linkedRecord), "reject a storage-file symlink before read or rewrite")
        let nested = fixtureRoot.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try v4RecordData.write(to: nested.appendingPathComponent("session-nested.json"))
        let futureRecord = fixtureRoot.appendingPathComponent("session-future.json", isDirectory: false)
        try Data(#"{"version":5,"record":{}}"#.utf8).write(to: futureRecord)

        let scan = scanProjectionCacheRecords(
            in: fixtureRoot,
            matching: ["session-1", "session-link", "session-nested", "session-future", "../escape"]
        )
        expect(scan.records.map(\.lastPathComponent) == ["session-1.json"], "accept only direct regular v4 cache records")
        expect(
            scan.failures.count == 2
                && scan.failures.contains { $0.contains("session-link.json") }
                && scan.failures.contains { $0.contains("session-future.json") },
            "fail closed on matching symlink and future projection-cache records"
        )
        expect(
            (try? Data(contentsOf: otherRecord)) == v4RecordData,
            "leave an unselected v4 cache record byte-identical"
        )
    } catch {
        failures.append("projection-cache filesystem fixture failed: \(error.localizedDescription)")
    }

    if failures.isEmpty {
        print("Self-test passed: alpha channel, token redaction, semantic versioning, chrome luminance and archived session cleanup")
        return 0
    }

    for failure in failures {
        fputs("Self-test failed: \(failure)\n", stderr)
    }
    return 1
}

if CommandLine.arguments.contains("--self-test") {
    Darwin.exit(runSelfTests())
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
