#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/macos/Build/Products/Release/clean_mac.app"
DIST_DIR="$ROOT_DIR/dist"
ZIP_PATH="$DIST_DIR/CleanMac-macos-release.zip"

cd "$ROOT_DIR"

echo "==> Resolving dependencies"
flutter pub get

echo "==> Analyzing"
flutter analyze

echo "==> Running tests"
flutter test

echo "==> Building macOS release"
flutter build macos --release

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"

echo "==> Creating zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Validating zip"
unzip -t "$ZIP_PATH" >/dev/null

echo "==> Done"
echo "$ZIP_PATH"
