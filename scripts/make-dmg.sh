#!/bin/bash
# 신규 설치용 DMG를 만든다: 앱 → Applications 로 끌어다 놓으라는 안내 창 + 서명·공증·스테이플.
# 앱 이름에 의존하지 않으므로 다른 macOS 앱도 그대로 쓸 수 있다 (배경 문구만 scripts/dmg 에서 바꾼다).
#
# 사용법: ./scripts/make-dmg.sh <공증·스테이플된 앱이 든 zip> <version>
#   결과: zip 옆에 <App>-<version>.dmg
# 필요: brew install create-dmg / notarytool 키체인 프로필(NOTARY_PROFILE, 기본 "notarytool")

set -euo pipefail

ZIP_PATH="${1:?zip 경로가 필요합니다}"
VERSION="${2:?버전이 필요합니다}"
SIGN_ID="${SIGN_ID:-Developer ID Application: Tving Co.,Ltd (635U6G6DF4)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKGROUND="${PROJECT_DIR}/scripts/dmg/background.tiff"   # 600x400, 아이콘 좌표는 아래와 맞춰 그렸다

log() { echo "💿 $1"; }
err() { echo "❌ $1" >&2; exit 1; }

command -v create-dmg >/dev/null || err "create-dmg가 없습니다: brew install create-dmg"
[ -f "$ZIP_PATH" ] || err "zip이 없습니다: $ZIP_PATH"
[ -f "$BACKGROUND" ] || err "배경 이미지가 없습니다: $BACKGROUND"

TITLE="$(basename "$ZIP_PATH" | sed -E "s/-${VERSION}\.zip$//")"
DMG_PATH="$(dirname "$ZIP_PATH")/${TITLE}-${VERSION}.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto -x -k "$ZIP_PATH" "$STAGE"
APP_NAME="$(cd "$STAGE" && ls -d *.app | head -1)"
[ -n "$APP_NAME" ] || err "zip 안에 .app이 없습니다"
xcrun stapler validate "$STAGE/$APP_NAME" >/dev/null || err "zip 안의 앱이 공증·스테이플되지 않았습니다"

log "DMG 생성: $(basename "$DMG_PATH")"
rm -f "$DMG_PATH"
create-dmg \
    --volname "$TITLE" \
    --background "$BACKGROUND" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 112 \
    --text-size 13 \
    --icon "$APP_NAME" 150 200 \
    --hide-extension "$APP_NAME" \
    --app-drop-link 450 200 \
    --no-internet-enable \
    "$DMG_PATH" "$STAGE"

log "서명·공증..."
codesign --force --sign "$SIGN_ID" --timestamp "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
spctl -a -t open --context context:primary-signature -v "$DMG_PATH" 2>&1 | grep -q accepted \
    || err "Gatekeeper가 DMG를 거부합니다"

log "완료: $DMG_PATH"
