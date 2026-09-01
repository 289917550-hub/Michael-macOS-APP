#!/usr/bin/env bash
#
# 打包可分发的安装包：通用二进制（arm64 + x86_64）→ .app → .pkg + .dmg
#
# 与 build.sh 的区别：build.sh 只编本机架构，用于日常开发；
# package.sh 产出能装到别的 Mac 上的安装包。
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DisplayToggle"
VERSION="1.1.0"
DEPLOY="13.0"          # 最低系统版本（Ventura）
IDENT="com.local.displaytoggle"

APP="${APP_NAME}.app"
CONTENTS="${APP}/Contents"
OUT="dist"
STAGE=".stage"

echo "▶ 编译 arm64 ..."
swiftc -O -target "arm64-apple-macosx${DEPLOY}" -o .build/dt_arm64 Sources/*.swift

echo "▶ 编译 x86_64 ..."
swiftc -O -target "x86_64-apple-macosx${DEPLOY}" -o .build/dt_x86 Sources/*.swift

echo "▶ 合并为通用二进制 ..."
lipo -create .build/dt_arm64 .build/dt_x86 -output .build/dt_universal

echo "▶ 组装 ${APP} ..."
rm -rf "${APP}" "${STAGE}" "${OUT}"
mkdir -p "${CONTENTS}/MacOS" "${OUT}" "${STAGE}"
cp .build/dt_universal "${CONTENTS}/MacOS/${APP_NAME}"
cp Info.plist "${CONTENTS}/Info.plist"

echo "▶ 签名 ..."
if security find-identity -v -p codesigning 2>/dev/null | grep -q "valid identities found" &&
   ! security find-identity -v -p codesigning 2>/dev/null | grep -q "0 valid identities found"; then
    # 有可用的 Developer ID 就用它签（分发到别的机器不会被 Gatekeeper 拦）
    SIGN_ID="$(security find-identity -v -p codesigning | awk -F'"' 'NR==1{print $2}')"
    echo "   使用身份：${SIGN_ID}"
    codesign --force --deep --options runtime --sign "${SIGN_ID}" "${APP}"
else
    echo "   未找到开发者证书 → 使用 ad-hoc 签名"
    echo "   （装到其他 Mac 上首次打开需右键 → 打开，详见 安装说明.md）"
    codesign --force --deep --sign - "${APP}"
fi

echo "▶ 生成 .pkg ..."
pkgbuild --identifier "${IDENT}" \
         --version "${VERSION}" \
         --install-location /Applications \
         --component "${APP}" \
         "${OUT}/${APP_NAME}-${VERSION}.pkg"

echo "▶ 生成 .dmg ..."
cp -R "${APP}" "${STAGE}/"
ln -sf /Applications "${STAGE}/Applications"
cp 安装说明.md "${STAGE}/安装说明.txt" 2>/dev/null || true
cp README.md    "${STAGE}/技术说明.txt"   2>/dev/null || true
hdiutil create -volname "${APP_NAME}" \
               -srcfolder "${STAGE}" \
               -ov -format UDZO \
               "${OUT}/${APP_NAME}-${VERSION}.dmg" >/dev/null
rm -rf "${STAGE}"

echo
echo "✔ 打包完成"
echo
ls -lh "${OUT}"
echo
echo "架构检查："
lipo -archs "${CONTENTS}/MacOS/${APP_NAME}"
echo "签名检查："
codesign -dv "${APP}" 2>&1 | head -3
