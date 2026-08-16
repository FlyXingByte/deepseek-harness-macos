# Unofficial macOS Launcher v2.3.1

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
