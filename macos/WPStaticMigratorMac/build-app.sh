#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_ROOT="$SCRIPT_DIR/.build/release"
APP="$SCRIPT_DIR/dist/WP Static Migrator.app"

cd "$SCRIPT_DIR"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Runtime"
cp "$BUILD_ROOT/WPStaticMigratorMac" "$APP/Contents/MacOS/WPStaticMigratorMac"
cp -R "$REPO_ROOT/bin" "$REPO_ROOT/scripts" "$REPO_ROOT/src" "$APP/Contents/Resources/Runtime/"
cp "$REPO_ROOT/config.json" "$REPO_ROOT/package.json" "$REPO_ROOT/package-lock.json" "$APP/Contents/Resources/Runtime/"
if [[ -d "$REPO_ROOT/node_modules" ]]; then
  cp -R "$REPO_ROOT/node_modules" "$APP/Contents/Resources/Runtime/node_modules"
else
  echo "node_modules がありません。先にリポジトリ直下で npm install を実行してください。" >&2
  exit 1
fi
cp "$SCRIPT_DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$SCRIPT_DIR/Resources/AppIcon-master.png" "$APP/Contents/Resources/AppIcon-master.png"
ASSET_OUTPUT="$SCRIPT_DIR/.build/asset-output"
rm -rf "$ASSET_OUTPUT"
mkdir -p "$ASSET_OUTPUT"
xcrun actool \
  --compile "$ASSET_OUTPUT" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$ASSET_OUTPUT/asset-info.plist" \
  "$SCRIPT_DIR/Resources/Assets.xcassets" >/dev/null
cp "$ASSET_OUTPUT/Assets.car" "$APP/Contents/Resources/Assets.car"
cp "$ASSET_OUTPUT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -n 1)"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP"
  echo "Signed with: $SIGNING_IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Warning: Developer ID Application certificate not found; used ad-hoc signing." >&2
fi
echo "Built: $APP"
