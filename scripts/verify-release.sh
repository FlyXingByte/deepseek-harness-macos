#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly DIST_DIR="${PROJECT_ROOT}/dist"
readonly APP_PATH="${DIST_DIR}/DeepSeek Harness.app"
readonly VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "${APP_PATH}/Contents/Info.plist")"
readonly DMG_FILENAME="DeepSeek-Harness-v${VERSION}-macOS-arm64.dmg"
readonly DMG_PATH="${DIST_DIR}/${DMG_FILENAME}"
readonly CHECKSUM_PATH="${DIST_DIR}/${DMG_FILENAME}.sha256"
readonly MOUNT_DIR="$(/usr/bin/mktemp -d /private/tmp/deepseek-harness-mount.XXXXXX)"
MOUNTED=0

cleanup() {
    if [[ "${MOUNTED}" == "1" ]]; then
        /usr/bin/hdiutil detach "${MOUNT_DIR}" >/dev/null
    fi
    case "${MOUNT_DIR}" in
        /private/tmp/deepseek-harness-mount.*) /bin/rmdir "${MOUNT_DIR}" 2>/dev/null || true ;;
    esac
}
trap cleanup EXIT INT TERM

for required_path in "${APP_PATH}" "${DMG_PATH}" "${CHECKSUM_PATH}"; do
    [[ -e "${required_path}" ]] || {
        print -u2 "Missing release artifact: ${required_path}"
        exit 1
    }
done

/usr/bin/plutil -lint "${APP_PATH}/Contents/Info.plist"
/usr/bin/codesign --verify --strict --verbose=2 "${APP_PATH}"
/usr/bin/file "${APP_PATH}/Contents/MacOS/DeepSeekHarnessApp" | /usr/bin/grep -F "arm64" >/dev/null
"${APP_PATH}/Contents/MacOS/DeepSeekHarnessApp" --self-test

if /usr/bin/strings "${APP_PATH}/Contents/MacOS/DeepSeekHarnessApp" | /usr/bin/grep -E '/Users/[^/]+/(Documents|Desktop|Downloads|Applications|\.codex)/' >/dev/null; then
    print -u2 "Release binary contains a private machine path."
    exit 1
fi

if /usr/bin/find "${APP_PATH}" -type f -print | /usr/bin/grep -E '\.credentials\.yaml$|/\.env$|harness-web\.log$' >/dev/null; then
    print -u2 "Release bundle contains a credential, environment, or log file."
    exit 1
fi

(
    cd "${DIST_DIR}"
    /usr/bin/shasum -a 256 -c "${DMG_FILENAME}.sha256"
)
/usr/bin/hdiutil verify "${DMG_PATH}"
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "${MOUNT_DIR}" "${DMG_PATH}" >/dev/null
MOUNTED=1

[[ -d "${MOUNT_DIR}/DeepSeek Harness.app" ]]
[[ -L "${MOUNT_DIR}/Applications" ]]
[[ "$(/usr/bin/readlink "${MOUNT_DIR}/Applications")" == "/Applications" ]]
[[ -f "${MOUNT_DIR}/Licenses/Launcher-MIT.txt" ]]
[[ -f "${MOUNT_DIR}/Licenses/DeepSeek-Harness-MIT.txt" ]]
/usr/bin/codesign --verify --strict --verbose=2 "${MOUNT_DIR}/DeepSeek Harness.app"

if /usr/sbin/spctl --assess --type execute --verbose=2 "${APP_PATH}" >/dev/null 2>&1; then
    print "Gatekeeper: accepted"
else
    print "Gatekeeper: not notarized (expected for this unsigned beta)"
fi

print "Release verification passed for v${VERSION}."
