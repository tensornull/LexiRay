#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version-without-v>" >&2
  exit 2
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/release/LexiRay.app"
DMG_PATH="$ROOT_DIR/build/LexiRay-$VERSION.dmg"
SHA_PATH="$ROOT_DIR/build/LexiRay-$VERSION.dmg.sha256"

if [[ "$VERSION" == v* ]]; then
  echo "Pass the version without a leading v. Example: $0 0.1.2" >&2
  exit 2
fi

cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 127
fi

rm -rf "$APP_PATH" "$DMG_PATH" "$SHA_PATH"
xcodegen generate

xcodebuild build \
  -project "$ROOT_DIR/LexiRay.xcodeproj" \
  -scheme LexiRay \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT_DIR/build/DerivedData" \
  CONFIGURATION_BUILD_DIR="$ROOT_DIR/build/release" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_COMPILATION_MODE=wholemodule

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [[ "$app_version" != "$VERSION" ]]; then
  echo "Unexpected app version: $app_version, expected $VERSION." >&2
  exit 1
fi

"$ROOT_DIR/script/import_release_signing_identity.sh"
"$ROOT_DIR/script/sign_release_app.sh" "$APP_PATH"

/usr/bin/hdiutil create -volname "LexiRay" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
"$ROOT_DIR/script/verify_release_dmg.sh" "$DMG_PATH" "$VERSION"
(cd "$ROOT_DIR/build" && /usr/bin/shasum -a 256 "LexiRay-$VERSION.dmg" >"LexiRay-$VERSION.dmg.sha256")
test -s "$SHA_PATH"

echo "Packaged signed release DMG: $DMG_PATH"
echo "SHA-256: $SHA_PATH"
