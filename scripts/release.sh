#!/bin/bash
# Prog 릴리즈 스크립트
# 사용법: ./scripts/release.sh <version>
# 예시: ./scripts/release.sh 1.1.0
# 먼저 릴리스 노트를 docs/release-notes/<version>.md 에 쓴다 — 업데이트 창과 GitHub 릴리스에 같은 내용이 나간다.

set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "사용법: $0 <version>"
    echo "예시: $0 1.1.0"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="${PROJECT_DIR}/releases/${VERSION}"
NOTES_MD="${PROJECT_DIR}/docs/release-notes/${VERSION}.md"
APP_NAME="Prog"
SCHEME="EyeProxy"
SPARKLE_BIN="${HOME}/Library/Developer/Xcode/DerivedData/EyeProxy-*/SourcePackages/artifacts/sparkle/Sparkle/bin"
FEED_URL="https://tving-prog.web.app/appcast.xml"   # .firebaserc 의 hosting 사이트와 일치해야 한다

log() { echo "🚀 $1"; }
err() { echo "❌ $1" >&2; exit 1; }

# Sparkle 도구 경로 확인
SIGN_UPDATE=$(find ${SPARKLE_BIN} -name "sign_update" -maxdepth 1 2>/dev/null | head -1)
GENERATE_APPCAST=$(find ${SPARKLE_BIN} -name "generate_appcast" -maxdepth 1 2>/dev/null | head -1)
[ -z "$SIGN_UPDATE" ] && err "sign_update를 찾을 수 없습니다. Xcode에서 먼저 빌드하세요."
[ -z "$GENERATE_APPCAST" ] && err "generate_appcast를 찾을 수 없습니다."
command -v firebase >/dev/null || err "firebase CLI가 없습니다: brew install firebase-cli"
command -v create-dmg >/dev/null || err "create-dmg가 없습니다: brew install create-dmg"
[ -f "$NOTES_MD" ] || err "릴리스 노트가 없습니다: docs/release-notes/${VERSION}.md"

# 잘못된 피드 주소로 빌드하면 그 버전을 설치한 사람은 다시는 업데이트를 못 받는다
PLIST_FEED=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "${PROJECT_DIR}/EyeProxy/Info.plist")
[ "$PLIST_FEED" = "$FEED_URL" ] || err "Info.plist SUFeedURL(${PLIST_FEED})이 ${FEED_URL}과 다릅니다."

# 1. 버전 업데이트
log "버전을 ${VERSION}으로 업데이트..."
cd "$PROJECT_DIR"
sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"${VERSION}\"/" project.yml
sed -i '' "s/<string>[0-9]*\.[0-9]*\.[0-9]*<\/string>/<string>${VERSION}<\/string>/" EyeProxy/Info.plist

# 빌드 번호 증가
CURRENT_BUILD=$(grep "CURRENT_PROJECT_VERSION" project.yml | head -1 | sed 's/.*: *"\{0,1\}\([0-9]*\)"\{0,1\}/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"${NEW_BUILD}\"/" project.yml
sed -i '' "s/<key>CFBundleVersion<\/key>/<key>CFBundleVersion<\/key>/" EyeProxy/Info.plist
sed -i '' "/<key>CFBundleVersion<\/key>/{n;s/<string>[0-9]*<\/string>/<string>${NEW_BUILD}<\/string>/;}" EyeProxy/Info.plist
log "버전: ${VERSION} (빌드 ${NEW_BUILD})"

# 2. XcodeGen
log "프로젝트 재생성..."
xcodegen generate

# 3. Release 빌드 (unsigned — 아래 4단계에서 회사 Developer ID로 재서명)
log "Release 빌드 중 (unsigned)..."
xcodebuild build \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "${PROJECT_DIR}/.build" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tail -5

BUILD_DIR="${PROJECT_DIR}/.build/Build/Products/Release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
[ -d "$APP_PATH" ] || err "앱 빌드 실패: ${APP_PATH}"
log "빌드 완료: ${APP_PATH}"

# 4. ZIP 패키징
mkdir -p "$RELEASE_DIR"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
log "Extended attributes 및 Apple Double 파일 제거..."
xattr -cr "${APP_PATH}"
find "${APP_PATH}" -name '._*' -delete
log "코드 재서명 (Developer ID + Hardened Runtime)..."
codesign --deep --force --sign "Developer ID Application: Tving Co.,Ltd (635U6G6DF4)" --timestamp --options runtime "${APP_PATH}"
codesign --force --sign "Developer ID Application: Tving Co.,Ltd (635U6G6DF4)" --timestamp --options runtime --entitlements "${PROJECT_DIR}/EyeProxy/EyeProxy.release.entitlements" "${APP_PATH}"
log "Notarization 제출..."
ditto -c -k --norsrc --keepParent "${APP_PATH}" "${RELEASE_DIR}/${ZIP_NAME}.tmp"
xcrun notarytool submit "${RELEASE_DIR}/${ZIP_NAME}.tmp" --keychain-profile "notarytool" --wait
rm -f "${RELEASE_DIR}/${ZIP_NAME}.tmp"
log "Notarization 티켓 스테이플..."
xcrun stapler staple "${APP_PATH}"
log "ZIP 생성: ${ZIP_NAME}"
cd "$BUILD_DIR"
export COPYFILE_DISABLE=1
ditto -c -k --norsrc --keepParent "${APP_NAME}.app" "$ZIP_PATH"
unset COPYFILE_DISABLE
cd "$PROJECT_DIR"

# 5. EdDSA 서명
log "EdDSA 서명..."
SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" 2>&1)
log "서명 정보: ${SIGNATURE}"

# 6. 신규 설치용 DMG (안내 창 + 서명·공증)
"${PROJECT_DIR}/scripts/make-dmg.sh" "$ZIP_PATH" "$VERSION"

# 7. Firebase Hosting 배포 (피드 + zip) — DMG는 GitHub Release에 첨부한다
ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
ED_SIG=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//')
[ -n "$ED_SIG" ] || err "EdDSA 서명을 얻지 못했습니다."
MIN_SYS="15.0"
NOTES_HTML="${RELEASE_DIR}/release-notes.html"
python3 "${PROJECT_DIR}/scripts/notes-html.py" "$NOTES_MD" "$VERSION" > "$NOTES_HTML"
DOWNLOAD_URL=$("${PROJECT_DIR}/scripts/publish-firebase.sh" "$ZIP_PATH" "$VERSION" "$NEW_BUILD" "$ED_SIG" "$MIN_SYS" "$NOTES_HTML" \
    | tee /dev/stderr | sed -n 's/^DOWNLOAD_URL=//p')
[ -n "$DOWNLOAD_URL" ] || err "Firebase 배포 실패"

# 8. 이전 피드(docs/appcast.xml, 개인 레포 GitHub Pages) 갱신
# ponytail: 1.1.1 이하 설치본이 새 피드로 넘어오기 위한 다리. 개인 레포를 비공개로 돌린 뒤에는 이 단계를 지운다.
log "이전 피드(docs/appcast.xml) 갱신..."
PUB_DATE=$(date -R)
NEW_ITEM="        <item>
            <title>${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${NEW_BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_SYS}</sparkle:minimumSystemVersion>
            <description><![CDATA[$(cat "$NOTES_HTML")]]></description>
            <enclosure url=\"${DOWNLOAD_URL}\" length=\"${ZIP_SIZE}\" type=\"application/octet-stream\" sparkle:edSignature=\"${ED_SIG}\"/>
        </item>"
ITEM_FILE=$(mktemp)
echo "$NEW_ITEM" > "$ITEM_FILE"
python3 - "$VERSION" "$ITEM_FILE" << 'PYEOF'
import re, sys
version = sys.argv[1]
new_item = open(sys.argv[2]).read().rstrip('\n')
xml = open('docs/appcast.xml').read()
pattern = r'\s*<item>.*?<sparkle:shortVersionString>' + re.escape(version) + r'</sparkle:shortVersionString>.*?</item>'
xml = re.sub(pattern, '', xml, flags=re.DOTALL)
xml = xml.replace('</title>\n', '</title>\n' + new_item + '\n', 1)
open('docs/appcast.xml', 'w').write(xml)
PYEOF
rm -f "$ITEM_FILE"

# 9. .build 정리
rm -rf "${PROJECT_DIR}/.build"

echo ""
log "=== 릴리즈 완료: ${FEED_URL} ==="
echo ""
echo "📦 ZIP: ${ZIP_PATH}"
echo "💿 DMG: ${ZIP_PATH%.zip}.dmg"
echo ""
echo "다음 단계:"
echo "  1. git add -A && git commit -m \"release: v${VERSION}\" && git tag v${VERSION}"
echo "  2. git push origin main --tags                # TvingCorp 레포"
echo "  3. git push personal main                     # 이전 피드(Pages) 갱신 — 다리 릴리스 기간에만"
echo "  4. gh release create v${VERSION} \"${ZIP_PATH%.zip}.dmg\" \"${ZIP_PATH}\" --title \"v${VERSION}\" --notes-file docs/release-notes/${VERSION}.md   # 신규 설치용 DMG"
