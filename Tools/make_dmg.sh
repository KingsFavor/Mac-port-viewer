#!/bin/bash
# 배경/레이아웃이 적용된 설치용 DMG 를 만든다.
# 사용법: Tools/make_dmg.sh <앱경로> <출력.dmg> [볼륨이름]
set -euo pipefail

APP_PATH="$1"
DMG_OUT="$2"
VOL_NAME="${3:-Port Killer}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BG_TIFF="${ROOT}/Tools/dmg-assets/background.tiff"

# 배경 에셋이 없으면 생성
if [ ! -f "${BG_TIFF}" ]; then
    echo "▶ DMG 배경 생성 중..."
    swift "${ROOT}/Tools/GenerateDMGBackground.swift" "${ROOT}/Tools/dmg-assets/background.png" 1
    swift "${ROOT}/Tools/GenerateDMGBackground.swift" "${ROOT}/Tools/dmg-assets/background@2x.png" 2
    tiffutil -cathidpicheck "${ROOT}/Tools/dmg-assets/background.png" \
        "${ROOT}/Tools/dmg-assets/background@2x.png" -out "${BG_TIFF}"
fi

APP_NAME="$(basename "${APP_PATH}")"
TMP_DIR="$(mktemp -d)"
STAGE="${TMP_DIR}/stage"
RW_DMG="${TMP_DIR}/rw.dmg"
mkdir -p "${STAGE}/.background"

cp -R "${APP_PATH}" "${STAGE}/${APP_NAME}"
cp "${BG_TIFF}" "${STAGE}/.background/background.tiff"
ln -s /Applications "${STAGE}/Applications"

# 용량 계산 (앱 크기 + 여유)
SIZE_KB=$(du -sk "${STAGE}" | awk '{print $1}')
SIZE_MB=$(( SIZE_KB / 1024 + 40 ))

echo "▶ 임시 DMG 생성 (${SIZE_MB}MB)..."
hdiutil create -srcfolder "${STAGE}" -volname "${VOL_NAME}" -fs HFS+ \
    -format UDRW -size "${SIZE_MB}m" "${RW_DMG}" >/dev/null

echo "▶ 마운트..."
MOUNT_DIR="/Volumes/${VOL_NAME}"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}" | grep -E '^/dev/' | head -1 | awk '{print $1}')
sleep 2

# Finder 창 스타일 지정 (헤드리스 환경에서 실패할 수 있으므로 실패해도 계속 진행)
echo "▶ 창 레이아웃 적용..."
osascript <<APPLESCRIPT || echo "  (창 스타일 적용 실패 — 기본 레이아웃으로 진행)"
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 520}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.tiff"
        set position of item "${APP_NAME}" of container window to {150, 200}
        set position of item "Applications" of container window to {490, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
echo "▶ 언마운트..."
hdiutil detach "${DEV}" >/dev/null 2>&1 || hdiutil detach "${DEV}" -force >/dev/null 2>&1 || true
sleep 1

echo "▶ 압축 DMG 로 변환..."
rm -f "${DMG_OUT}"
hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_OUT}" >/dev/null

rm -rf "${TMP_DIR}"
echo "✅ DMG 완료: ${DMG_OUT}"
