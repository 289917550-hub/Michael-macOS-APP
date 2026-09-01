#!/usr/bin/env bash
#
# 把 Swift 源码编译并打包成 DisplayToggle.app
# 指定部署目标 macOS 13.0（Ventura），确保在所有支持的版本上运行
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DisplayToggle"
APP="${APP_NAME}.app"
CONTENTS="${APP}/Contents"
DEPLOY="13.0"

echo "▶ 编译 Swift 源码..."
rm -rf "${APP}"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

# 尝试编译通用二进制（arm64 + x86_64），失败则只编 arm64
TMP_ARM64="/tmp/${APP_NAME}_arm64_$$"
TMP_X86="/tmp/${APP_NAME}_x86_$$"

echo "  编译 arm64 ..."
swiftc -O -target "arm64-apple-macosx${DEPLOY}" -o "$TMP_ARM64" Sources/*.swift

if swiftc -O -target "x86_64-apple-macosx${DEPLOY}" -o "$TMP_X86" Sources/*.swift 2>/dev/null; then
    echo "  编译 x86_64 ..."
    lipo -create "$TMP_ARM64" "$TMP_X86" -output "${CONTENTS}/MacOS/${APP_NAME}"
    rm -f "$TMP_ARM64" "$TMP_X86"
    echo "  通用二进制（arm64 + x86_64）"
else
    echo "  x86_64 编译不可用，仅 arm64"
    cp "$TMP_ARM64" "${CONTENTS}/MacOS/${APP_NAME}"
    rm -f "$TMP_ARM64" "$TMP_X86"
fi

cp Info.plist "${CONTENTS}/Info.plist"

echo "▶ 签名（ad-hoc）..."
codesign --force --deep --sign - "${APP}" 2>/dev/null \
  || echo "  （签名失败，可忽略；未签名的 app 首次运行需在右键菜单里选择「打开」）"

echo
echo "✔ 构建完成：$(pwd)/${APP}"
echo "  最低系统：macOS ${DEPLOY} (Ventura)"
echo "  架构：$(lipo -archs "${CONTENTS}/MacOS/${APP_NAME}" 2>/dev/null || echo 'arm64')"
echo
echo "  启动菜单栏程序：  open ${APP}"
echo "  查看显示器列表：  ${APP}/Contents/MacOS/${APP_NAME} --list"
echo "  开关自检：        ${APP}/Contents/MacOS/${APP_NAME} --selftest"
