#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  make-release.sh  —  Build BetterFinder, sign, notarize, and package as DMG
#
#  Usage:
#    bash make-release.sh              # version = today (YYYY-MM-DD)
#    VERSION=1.0.0 bash make-release.sh
#
#  Required env vars for notarization (skip to build unsigned locally):
#    APPLE_ID        — your Apple ID email
#    APPLE_PASSWORD  — app-specific password from appleid.apple.com
#    TEAM_ID         — your Apple Developer Team ID
#
#  Output:
#    build/BetterFinder-<version>.dmg
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

APP_NAME="BetterFinder"
SCHEME="BetterFinder"
VERSION="${VERSION:-$(date +%Y-%m-%d)}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
TMP_DIR="$(mktemp -d)"
DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Franceco Albano (DZ5Q67NB9G)}"
APPLE_ID="${APPLE_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"
TEAM_ID="${TEAM_ID:-DZ5Q67NB9G}"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ── 1. Clean ──────────────────────────────────────────────────────
echo "▸ Cleaning…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── 2. Build Release ──────────────────────────────────────────────
echo "▸ Building $APP_NAME $VERSION (Release)…"
xcodebuild \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE="Manual" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--deep --options=runtime --timestamp" \
    MARKETING_VERSION="$VERSION" \
    build 2>&1 | grep -E "(error:|warning:|Build succeeded|Build FAILED|▸)" || true

APP_PATH="$BUILD_DIR/Release/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ App bundle not found at: $APP_PATH"
    exit 1
fi
echo "  App bundle: $APP_PATH"

# ── 3. Notarize (skip if credentials not provided) ────────────────
if [[ -n "$APPLE_ID" && -n "$APPLE_PASSWORD" ]]; then
    echo "▸ Zipping app for notarization…"
    ZIP_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.zip"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "▸ Submitting for notarization…"
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    echo "▸ Stapling notarization ticket…"
    xcrun stapler staple "$APP_PATH"
    rm -f "$ZIP_PATH"
else
    echo "  (skipping notarization — APPLE_ID/APPLE_PASSWORD not set)"
fi

# ── 4. Stage DMG contents ─────────────────────────────────────────
echo "▸ Staging DMG contents…"
cp -R "$APP_PATH" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

# ── 5. Create DMG ─────────────────────────────────────────────────
echo "▸ Creating DMG…"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

# ── 6. Notarize DMG too ───────────────────────────────────────────
if [[ -n "$APPLE_ID" && -n "$APPLE_PASSWORD" ]]; then
    echo "▸ Notarizing DMG…"
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    echo "▸ Stapling DMG…"
    xcrun stapler staple "$DMG_PATH"
fi

SIZE=$(du -sh "$DMG_PATH" | cut -f1)
echo ""
echo "✓ $APP_NAME $VERSION  ($SIZE)"
echo "  $DMG_PATH"
