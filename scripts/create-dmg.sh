#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly DIST_DIR="${PROJECT_ROOT}/dist"
readonly APP_PATH="${DIST_DIR}/DeepSeek Harness.app"

[[ -d "${APP_PATH}" ]] || {
    print -u2 "Build the app first: ${SCRIPT_DIR}/build.sh"
    exit 1
}

readonly VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "${APP_PATH}/Contents/Info.plist")"
readonly DMG_FILENAME="DeepSeek-Harness-v${VERSION}-macOS-arm64.dmg"
readonly DMG_PATH="${DIST_DIR}/${DMG_FILENAME}"
readonly CHECKSUM_PATH="${DIST_DIR}/${DMG_FILENAME}.sha256"
readonly STAGING_DIR="$(/usr/bin/mktemp -d /private/tmp/deepseek-harness-dmg.XXXXXX)"

cleanup() {
    case "${STAGING_DIR}" in
        /private/tmp/deepseek-harness-dmg.*) /bin/rm -rf -- "${STAGING_DIR}" ;;
    esac
}
trap cleanup EXIT INT TERM

/usr/bin/ditto "${APP_PATH}" "${STAGING_DIR}/DeepSeek Harness.app"
/bin/ln -s /Applications "${STAGING_DIR}/Applications"
/bin/cp "${PROJECT_ROOT}/INSTALL.md" "${STAGING_DIR}/安装说明.md"
/bin/cp "${PROJECT_ROOT}/NOTICE.md" "${STAGING_DIR}/非官方声明.md"
/bin/mkdir -p "${STAGING_DIR}/Licenses"
/bin/cp "${PROJECT_ROOT}/LICENSE" "${STAGING_DIR}/Licenses/Launcher-MIT.txt"
/bin/cp "${PROJECT_ROOT}/LICENSES/DeepSeek-Harness-MIT.txt" "${STAGING_DIR}/Licenses/DeepSeek-Harness-MIT.txt"

/usr/bin/hdiutil create \
    -volname "DeepSeek Harness" \
    -srcfolder "${STAGING_DIR}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "${DMG_PATH}"

(
    cd "${DIST_DIR}"
    /usr/bin/shasum -a 256 "${DMG_FILENAME}" > "${DMG_FILENAME}.sha256"
)

print "Created ${DMG_PATH}"
print "Checksum ${CHECKSUM_PATH}"
