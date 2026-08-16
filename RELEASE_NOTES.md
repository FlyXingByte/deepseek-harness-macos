# Unofficial macOS Launcher v2.4.0

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
