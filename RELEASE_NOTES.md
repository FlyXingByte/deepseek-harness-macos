# Unofficial macOS Launcher v2.6.0

Step-by-step Harness core rollback release.

## Why this matters

Until now the launcher could only jump back to the bundled core, so a user who had moved forward across several official releases lost every intermediate version in a single step. This release keeps a history of the versions you actually ran, so a bad upgrade costs you one step back instead of all of them.

## Changed

- Replaced the “Restore bundled core” menu action with “Roll back to previous core”, which names the exact version it will return to.
- Records the outgoing version every time the core is switched, keeping up to 10 entries so repeated rollbacks walk back through the history and eventually reach the bundled version.
- Disables the menu item when no rollback target exists, instead of offering a no-op restore.
- The update confirmation sheet now points at the version you are leaving as the rollback target, and the rollback sheet reports how many further steps remain.

## Safety and compatibility

- The service remains bound to `127.0.0.1:3080`; this release does not expose Harness to the LAN.
- Model credentials, Harness sessions, workspaces, and the user-selected official core version are not migrated or copied by the launcher.
- Rollback targets are validated as semantic versions and are never allowed below the bundled `@deepseek-ai/dsh@0.1.0-rc.6`, so a launcher upgrade cannot leave an unusable version in the history.
- Version history starts accumulating from this release; core switches made by earlier builds cannot be reconstructed.

## Distribution status

This build is distributed as an ad-hoc signed, non-notarized prerelease. On first launch, use Finder → right-click → Open; do not disable Gatekeeper.

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
