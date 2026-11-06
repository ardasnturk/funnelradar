#!/usr/bin/env bash
# Builds, signs (Developer ID), notarizes and staples FunnelRadar for Mac and
# packages it as a DMG for GitHub Releases / Homebrew.
#
# Requirements:
#   * Xcode with a "Developer ID Application" certificate of team 5JMD3VSD7N
#   * dmgbuild for the designed DMG window: `pipx install dmgbuild`
#   * notarytool credentials stored once with:
#       xcrun notarytool store-credentials pilothouse-notary \
#         --apple-id <apple-id> --team-id 5JMD3VSD7N --password <app-specific-password>
#     (or set NOTARY_PROFILE to another stored profile)
#
# Output: dist/FunnelRadar-<version>.dmg (+ .sha256)
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-pilothouse-notary}"
VERSION="${VERSION:-$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')}"
BUILD="build/mac"
DIST="dist"
ARCHIVE="$BUILD/FunnelRadar.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/FunnelRadar.app"
DMG="$DIST/FunnelRadar-$VERSION.dmg"

rm -rf "$BUILD" && mkdir -p "$BUILD" "$DIST"

echo "▸ Archiving FunnelRadar $VERSION"
xcodebuild archive \
  -project FunnelRadar.xcodeproj -scheme FunnelRadar -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION"

echo "▸ Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/export/ExportOptions-mac.plist \
  -exportPath "$EXPORT"

echo "▸ Verifying signatures (app + embedded hub)"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP/Contents/MacOS/funnelradar-hub" 2>&1 | grep -E "Identifier|TeamIdentifier"

echo "▸ Notarizing the app"
ditto -c -k --keepParent "$APP" "$BUILD/FunnelRadar.zip"
xcrun notarytool submit "$BUILD/FunnelRadar.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

echo "▸ Building the DMG"
rm -f "$DMG"
DMGBUILD="${DMGBUILD:-$(command -v dmgbuild || true)}"
if [[ -n "$DMGBUILD" ]]; then
  # Designed window: background, icon positions (scripts/dmg/settings.py).
  "$DMGBUILD" -s scripts/dmg/settings.py -D app="$APP" "FunnelRadar" "$DMG"
elif [[ "${ALLOW_PLAIN_DMG:-0}" != "1" ]]; then
  # A release DMG without its designed window is a mistake, not a fallback.
  echo "dmgbuild not found. Install it (pipx install dmgbuild) or point DMGBUILD at it;" >&2
  echo "ALLOW_PLAIN_DMG=1 builds a plain DMG for local testing." >&2
  exit 1
else
  echo "  ALLOW_PLAIN_DMG=1 — building a plain DMG without the designed window"
  STAGING="$BUILD/dmg"
  mkdir -p "$STAGING"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "FunnelRadar" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
fi
codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "▸ Checking the app inside the DMG the way the in-app updater does"
CHECK="$BUILD/dmg-check"
rm -rf "$CHECK" && mkdir -p "$CHECK"
MOUNT=$(hdiutil attach -nobrowse -readonly -noautoopen "$DMG" | tail -1 | awk -F'\t' '{print $NF}')
ditto "$MOUNT/FunnelRadar.app" "$CHECK/FunnelRadar.app"
hdiutil detach "$MOUNT" -quiet
codesign --verify --deep --strict "$CHECK/FunnelRadar.app"

echo "▸ Notarizing the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

shasum -a 256 "$DMG" | tee "$DMG.sha256"

echo "✔ $DMG"
echo "Next: scripts/prepare-release.sh $VERSION"
