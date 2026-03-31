#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  make-release.sh  —  Build BetterFinder and package it as a DMG
#
#  Usage:
#    bash make-release.sh              # version = today (YYYY-MM-DD)
#    VERSION=1.0.0 bash make-release.sh
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
    CODE_SIGN_IDENTITY="-" \
    OTHER_CODE_SIGN_FLAGS="--deep" \
    MARKETING_VERSION="$VERSION" \
    build 2>&1 | grep -E "(error:|warning:|Build succeeded|Build FAILED|▸)" || true

APP_PATH="$BUILD_DIR/Release/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ App bundle not found at: $APP_PATH"
    exit 1
fi
echo "  App bundle: $APP_PATH"

# ── 3. Stage DMG contents ─────────────────────────────────────────
echo "▸ Staging DMG contents…"
cp -R "$APP_PATH" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

# ── 4. Create DMG ─────────────────────────────────────────────────
echo "▸ Creating DMG…"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

SIZE=$(du -sh "$DMG_PATH" | cut -f1)
echo ""
echo "✓ $APP_NAME $VERSION  ($SIZE)"
echo "  $DMG_PATH"
