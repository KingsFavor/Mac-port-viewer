#!/bin/bash
# PortKiller.app 번들을 빌드한다. (릴리즈 빌드 + Info.plist + ad-hoc 코드사인)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Port Killer"
BUNDLE_ID="com.portkiller.app"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"
BIN_NAME="PortKiller"

echo "▶ 릴리즈 빌드 중..."
swift build -c release

echo "▶ 앱 번들 구성 중: ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${BIN_NAME}" "${APP_DIR}/Contents/MacOS/${BIN_NAME}"

# 앱 아이콘 (없으면 생성)
ICNS="Sources/PortKiller/Resources/AppIcon.icns"
if [ ! -f "${ICNS}" ]; then
    echo "▶ 아이콘 생성 중..."
    swift Tools/GenerateIcon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o "${ICNS}"
fi
cp "${ICNS}" "${APP_DIR}/Contents/Resources/AppIcon.icns"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${BIN_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Port Killer — developer port manager</string>
</dict>
</plist>
PLIST

echo "▶ ad-hoc 코드사인..."
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true

echo "✅ 완료: ${APP_DIR}"
echo "   실행:      open \"${APP_DIR}\""
echo "   설치(선택): cp -R \"${APP_DIR}\" /Applications/"
