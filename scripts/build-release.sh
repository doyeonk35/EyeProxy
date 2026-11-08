#!/bin/bash
# Build Prog for release distribution
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="EyeProxy"
BUILD_DIR="$(pwd)/build"
DIST_DIR="$(pwd)/dist"
APP_NAME="Prog"

echo "=== Cleaning ==="
rm -rf "${BUILD_DIR}" "${DIST_DIR}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

xcodegen generate
echo "=== Building Release ==="
xcodebuild build \
    -project EyeProxy.xcodeproj \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "${BUILD_DIR}" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

echo "=== Packaging ==="
APP_PATH=$(find "${BUILD_DIR}" -name "${APP_NAME}.app" -type d | head -1)

if [ -z "${APP_PATH}" ]; then
    echo "ERROR: Could not find ${APP_NAME}.app"
    exit 1
fi

echo "=== Removing extended attributes and Apple Double files ==="
xattr -cr "${APP_PATH}"
find "${APP_PATH}" -name '._*' -delete

cp -R "${APP_PATH}" "${DIST_DIR}/"
cd "${DIST_DIR}"
export COPYFILE_DISABLE=1
zip -r "${APP_NAME}.zip" "${APP_NAME}.app"
unset COPYFILE_DISABLE

echo ""
echo "=== Done ==="
echo "App: ${DIST_DIR}/${APP_NAME}.app"
echo "Zip: ${DIST_DIR}/${APP_NAME}.zip"
