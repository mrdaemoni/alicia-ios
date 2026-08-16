#!/bin/bash
# Ship Alicia to TestFlight — archive, export, upload. One command.
#
#   ./ship.sh            # bump the build number, archive, upload
#   ./ship.sh --no-bump  # re-upload the current build number (rarely what you want:
#                        # App Store Connect rejects a build number it has seen)
#
# Credentials live in ~/.appstoreconnect/config (key id + issuer) and
# ~/.appstoreconnect/private_keys/AuthKey_<id>.p8 — both chmod 600, both
# OUTSIDE this repo, so a stray `git add -A` can never publish them.
#
# The 7-day cable ritual ended when the team went paid (profiles last a year);
# this ends the cable entirely — the build lands in TestFlight and installs
# over the air.

set -euo pipefail

cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CONFIG=~/.appstoreconnect/config
[ -f "$CONFIG" ] || { echo "!! missing $CONFIG (ASC_KEY_ID / ASC_ISSUER_ID / ASC_TEAM_ID)"; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ARCHIVE="$WORK/Alicia.xcarchive"
EXPORT="$WORK/export"

# ── Build number ──────────────────────────────────────────────────────────
# App Store Connect refuses a build number it has already seen, so every
# upload needs a fresh one. The marketing version (1.0) is what humans read;
# this is the thing that must simply always increase.
if [ "${1:-}" != "--no-bump" ]; then
  CURRENT=$(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' Alicia.xcodeproj/project.pbxproj | grep -oE '[0-9]+')
  NEXT=$((CURRENT + 1))
  sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT};/CURRENT_PROJECT_VERSION = ${NEXT};/g" \
    Alicia.xcodeproj/project.pbxproj
  echo "==> build ${CURRENT} → ${NEXT}"
fi
BUILD=$(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' Alicia.xcodeproj/project.pbxproj | grep -oE '[0-9]+')
VERSION=$(grep -m1 -oE 'MARKETING_VERSION = [0-9.]+' Alicia.xcodeproj/project.pbxproj | grep -oE '[0-9.]+')
TAG=$(grep -m1 -oE 'static let tag = "v[0-9]+"' Alicia/DesignSystem/ContourWaves.swift | grep -oE 'v[0-9]+')
echo "==> shipping ${TAG} as ${VERSION} (${BUILD})"

# ── Archive ───────────────────────────────────────────────────────────────
echo "==> archiving…"
xcodebuild -scheme Alicia -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" archive -allowProvisioningUpdates -quiet

# ── Export ────────────────────────────────────────────────────────────────
# The archive is signed for development; exporting re-signs it with the
# Apple Distribution certificate, which is what App Store Connect requires.
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>teamID</key><string>${ASC_TEAM_ID}</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "==> exporting…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates -quiet

# Prove it before spending a minute on the upload: a development-signed IPA
# is accepted by altool and then rejected server-side, minutes later.
if ! codesign -dvv "$EXPORT/Payload/Alicia.app" 2>&1 | grep -q "Apple Distribution"; then
  unzip -qo "$EXPORT/Alicia.ipa" -d "$WORK/check"
  codesign -dvv "$WORK/check/Payload/Alicia.app" 2>&1 | grep -q "Apple Distribution" || {
    echo "!! IPA is not distribution-signed — refusing to upload"; exit 1; }
fi

# ── Upload ────────────────────────────────────────────────────────────────
echo "==> uploading to App Store Connect…"
xcrun altool --upload-app -f "$EXPORT/Alicia.ipa" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo
echo "==> ${TAG} (${VERSION}/${BUILD}) uploaded."
echo "    Processing takes ~5–15 min, then it appears in TestFlight."
echo "    Internal testers get it with no Beta App Review."
echo "    Remember to commit the bumped build number."
