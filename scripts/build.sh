#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"

case "${PROJECT_ROOT}" in
    */deepseek-harness-macos) ;;
    *)
        print -u2 "Unexpected project root: ${PROJECT_ROOT}"
        exit 1
        ;;
esac

readonly SOURCE_FILE="${PROJECT_ROOT}/Sources/DeepSeekHarnessApp.swift"
readonly INFO_PLIST="${PROJECT_ROOT}/Resources/Info.plist"
readonly ICON_PNG="${PROJECT_ROOT}/Assets/DeepSeekHarness.png"
readonly ICON_ICNS="${PROJECT_ROOT}/Assets/DeepSeekHarness.icns"
readonly BUILD_DIR="${PROJECT_ROOT}/build"
readonly DIST_DIR="${PROJECT_ROOT}/dist"
readonly APP_PATH="${DIST_DIR}/DeepSeek Harness.app"
readonly APP_CONTENTS="${APP_PATH}/Contents"
readonly APP_BINARY="${APP_CONTENTS}/MacOS/DeepSeekHarnessApp"

for required_file in "${SOURCE_FILE}" "${INFO_PLIST}" "${ICON_PNG}" "${ICON_ICNS}"; do
    [[ -f "${required_file}" ]] || {
        print -u2 "Missing required file: ${required_file}"
        exit 1
    }
done

/usr/bin/plutil -lint "${INFO_PLIST}"
/bin/mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

if [[ -e "${APP_PATH}" ]]; then
    [[ "${APP_PATH}" == "${PROJECT_ROOT}/dist/DeepSeek Harness.app" ]] || {
        print -u2 "Refusing to replace unexpected path: ${APP_PATH}"
        exit 1
    }
    /bin/rm -rf -- "${APP_PATH}"
fi

/bin/mkdir -p "${APP_CONTENTS}/MacOS" "${APP_CONTENTS}/Resources"

/usr/bin/swiftc \
    -swift-version 5 \
    -target arm64-apple-macos12.0 \
    -O \
    -framework AppKit \
    -framework WebKit \
    "${SOURCE_FILE}" \
    -o "${APP_BINARY}"

/bin/chmod 755 "${APP_BINARY}"
/bin/cp "${INFO_PLIST}" "${APP_CONTENTS}/Info.plist"
/bin/cp "${ICON_PNG}" "${APP_CONTENTS}/Resources/DeepSeekHarness.png"
/bin/cp "${ICON_ICNS}" "${APP_CONTENTS}/Resources/DeepSeekHarness.icns"

/usr/bin/codesign \
    --force \
    --sign - \
    --options runtime \
    --timestamp=none \
    "${APP_PATH}"

/usr/bin/codesign --verify --strict --verbose=2 "${APP_PATH}"
/usr/bin/touch "${APP_PATH}"

print "Built ${APP_PATH}"
/usr/bin/file "${APP_BINARY}"
