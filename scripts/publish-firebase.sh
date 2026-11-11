#!/bin/bash
# Sparkle 업데이트(zip + appcast.xml)를 Firebase Hosting에 배포한다.
# DMG는 올리지 않는다 — 무료(Spark) 플랜은 .dmg 같은 실행 파일 업로드를 거부한다 (zip은 허용).
# 앱 이름에 의존하지 않으므로 다른 macOS 앱도 이 파일과 firebase.json, .firebaserc만
# 복사해 쓰면 된다. 앱마다 Hosting 사이트를 따로 두는 이유: 배포가 사이트 전체를 교체하기 때문.
#
# 사용법: ./scripts/publish-firebase.sh <zip> <version> <build> <edSignature> [minimumSystemVersion] [releaseNotes.html]
#   릴리스 노트 HTML을 주면 Sparkle 업데이트 창에 보인다(<description> CDATA).
#   .firebaserc 의 default 프로젝트와 hosting 타깃 "app"에 연결된 사이트로 배포한다.

set -euo pipefail

ZIP_PATH="${1:?zip 경로가 필요합니다}"
VERSION="${2:?버전이 필요합니다}"
BUILD="${3:?빌드 번호가 필요합니다}"
ED_SIG="${4:?EdDSA 서명이 필요합니다}"
MIN_SYS="${5:-14.0}"
NOTES_HTML="${6:-}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

log() { echo "🔥 $1"; }
err() { echo "❌ $1" >&2; exit 1; }

command -v firebase >/dev/null || err "firebase CLI가 없습니다: brew install firebase-cli"
[ -f "$ZIP_PATH" ] || err "zip이 없습니다: $ZIP_PATH"

read -r FB_PROJECT FB_SITE < <(python3 - <<'PY'
import json
rc = json.load(open(".firebaserc"))
project = rc["projects"]["default"]
print(project, rc["targets"][project]["hosting"]["app"][0])
PY
)
BASE_URL="https://${FB_SITE}.web.app"
TITLE="$(basename "$ZIP_PATH" | sed -E "s/-${VERSION}\.zip$//")"
ZIP_NAME="$(basename "$ZIP_PATH")"
PUBLIC_DIR="${PROJECT_DIR}/releases/hosting"   # firebase.json 의 public 과 같아야 한다

# 배포는 사이트 전체를 교체한다 — 최신 버전만 올린다 (Sparkle은 최신 항목만 쓴다).
rm -rf "$PUBLIC_DIR"
mkdir -p "${PUBLIC_DIR}/${VERSION}"
cp "$ZIP_PATH" "${PUBLIC_DIR}/${VERSION}/${ZIP_NAME}"
cp "$ZIP_PATH" "${PUBLIC_DIR}/${TITLE}.zip"   # 고정 주소 — README 다운로드 링크용

DESCRIPTION=""
if [ -n "$NOTES_HTML" ]; then
    [ -f "$NOTES_HTML" ] || err "릴리스 노트가 없습니다: $NOTES_HTML"
    grep -q ']]>' "$NOTES_HTML" && err "릴리스 노트에 ']]>'가 있으면 CDATA가 깨집니다"
    DESCRIPTION="<description><![CDATA[$(cat "$NOTES_HTML")]]></description>"
fi

cat > "${PUBLIC_DIR}/appcast.xml" <<XML
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>${TITLE}</title>
        <item>
            <title>${VERSION}</title>
            <pubDate>$(date -R)</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_SYS}</sparkle:minimumSystemVersion>
            ${DESCRIPTION}
            <enclosure url="${BASE_URL}/${VERSION}/${ZIP_NAME}" length="$(stat -f%z "$ZIP_PATH")" type="application/octet-stream" sparkle:edSignature="${ED_SIG}"/>
        </item>
    </channel>
</rss>
XML

log "${FB_PROJECT} / ${FB_SITE} 에 배포..."
firebase deploy --only hosting:app --project "$FB_PROJECT" --non-interactive -m "${TITLE} ${VERSION} (${BUILD})"

# 배포 결과 확인: 피드에 새 버전이 보이고 zip이 같은 크기로 받아져야 한다
curl -fsS "${BASE_URL}/appcast.xml" | grep -q "<sparkle:version>${BUILD}</sparkle:version>" \
    || err "피드에 빌드 ${BUILD}가 보이지 않습니다: ${BASE_URL}/appcast.xml"
REMOTE_SIZE=$(curl -fsSI "${BASE_URL}/${VERSION}/${ZIP_NAME}" | awk 'tolower($1)=="content-length:" {print $2}' | tr -d '\r')
[ "$REMOTE_SIZE" = "$(stat -f%z "$ZIP_PATH")" ] || err "zip 크기가 다릅니다 (원격 ${REMOTE_SIZE:-없음})"

log "배포 완료: ${BASE_URL}/appcast.xml (최신 zip: ${BASE_URL}/${TITLE}.zip)"
echo "DOWNLOAD_URL=${BASE_URL}/${VERSION}/${ZIP_NAME}"
