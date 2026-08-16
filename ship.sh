#!/bin/bash
# Ship Alicia to TestFlight — allocate, archive, verify, upload, and wait.
#
#   ./ship.sh            # reserve a build number and ship this branch
#   ./ship.sh --dry-run  # verify prerequisites and show the next number
#   ./ship.sh --verify-only # archive/export/inspect without reserving or upload
#
# Credentials remain under ~/.appstoreconnect and Alicia/Secrets.plist remains
# gitignored. This script never prints either credential and never changes git.

set -euo pipefail

cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DRY_RUN=false
VERIFY_ONLY=false
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=true ;;
  --verify-only) VERIFY_ONLY=true ;;
  *) echo "usage: ./ship.sh [--dry-run|--verify-only]"; exit 2 ;;
esac

APPSTORE_DIR="${ALICIA_ASC_DIR:-${HOME}/.appstoreconnect}"
CONFIG="$APPSTORE_DIR/config"
ASC_APP_ID="${ASC_APP_ID:-6801945776}"
SECRETS="Alicia/Secrets.plist"
STATE_FILE="$APPSTORE_DIR/alicia-ios-build-number"
LOCK_FILE="$APPSTORE_DIR/alicia-ios-build-number.lock"
LOCK_HELD=false
WORK=""

die() {
  echo "!! $*" >&2
  exit 1
}

cleanup() {
  if [ "$LOCK_HELD" = true ]; then
    release_allocator_lock
  fi
  if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then
    case "$WORK" in
      /tmp/tmp.*|/var/folders/*/T/tmp.*) rm -rf -- "$WORK" ;;
      *) echo "!! refusing to remove unexpected temporary path: $WORK" >&2 ;;
    esac
  fi
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

require_command curl
require_command git
require_command jq
require_command plutil
require_command shlock
require_command xcodebuild
require_command xcrun

[ -f "$CONFIG" ] \
  || die "missing $CONFIG (ASC_KEY_ID / ASC_ISSUER_ID / ASC_TEAM_ID)"
# shellcheck disable=SC1090
source "$CONFIG"
: "${ASC_KEY_ID:?missing ASC_KEY_ID in App Store Connect config}"
: "${ASC_ISSUER_ID:?missing ASC_ISSUER_ID in App Store Connect config}"
: "${ASC_TEAM_ID:?missing ASC_TEAM_ID in App Store Connect config}"

# Shipping uncommitted source would create a binary no branch can reproduce.
# Secrets.plist is ignored and therefore does not make this check dirty.
[ -z "$(git status --porcelain)" ] \
  || die "worktree has uncommitted files; commit the exact build before shipping"

BRANCH=$(git branch --show-current)
[ -n "$BRANCH" ] || die "detached HEAD; ship from a named branch"
COMMIT=$(git rev-parse --short=12 HEAD)

# A missing or malformed secret silently selects MockAliciaService. Fail before
# spending minutes archiving, and never print either value.
[ -r "$SECRETS" ] \
  || die "missing or unreadable $SECRETS; run scripts/provision-worktree.sh"
plutil -lint "$SECRETS" >/dev/null || die "$SECRETS is not a valid plist"
/usr/libexec/PlistBuddy -c 'Print :BaseURL' "$SECRETS" >/dev/null 2>&1 \
  || die "$SECRETS is missing BaseURL"
/usr/libexec/PlistBuddy -c 'Print :Token' "$SECRETS" >/dev/null 2>&1 \
  || die "$SECRETS is missing Token"

PROJECT_BUILD=$(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' Alicia.xcodeproj/project.pbxproj | grep -oE '[0-9]+')
VERSION=$(grep -m1 -oE 'MARKETING_VERSION = [0-9.]+' Alicia.xcodeproj/project.pbxproj | grep -oE '[0-9.]+')
BASE_TAG=$(grep -m1 -oE 'static let baseTag = "v[0-9]+"' Alicia/DesignSystem/ContourWaves.swift | grep -oE 'v[0-9]+')
[ -n "$PROJECT_BUILD" ] && [ -n "$VERSION" ] && [ -n "$BASE_TAG" ] \
  || die "could not read the app version settings"

generate_jwt() {
  local output token
  output=$(xcrun altool --generate-jwt \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1) \
    || die "App Store Connect authentication failed"
  token=$(printf '%s\n' "$output" | awk 'NF { line=$0 } END { print line }')
  case "$token" in
    *.*.*) printf '%s' "$token" ;;
    *) die "App Store Connect did not return a usable authentication token" ;;
  esac
}

highest_remote_build() {
  local jwt url response next version highest
  jwt=$(generate_jwt)
  url="https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=${ASC_APP_ID}&fields%5Bbuilds%5D=version&limit=200"
  highest=0

  while [ -n "$url" ]; do
    response=$(printf 'header = "Authorization: Bearer %s"\n' "$jwt" \
      | curl --config - -fsS "$url") \
      || die "could not query App Store Connect builds"
    printf '%s' "$response" | jq -e '.data | type == "array"' >/dev/null \
      || die "App Store Connect returned an unexpected builds response"

    while IFS= read -r version; do
      [ -z "$version" ] && continue
      case "$version" in
        *[!0-9]*) die "App Store Connect contains a non-integer build number; migrate it before using the allocator" ;;
      esac
      if [ "$version" -gt "$highest" ]; then highest=$version; fi
    done < <(printf '%s' "$response" | jq -r '.data[].attributes.version')

    next=$(printf '%s' "$response" | jq -r '.links.next // empty')
    url="$next"
  done

  printf '%s' "$highest"
}

read_local_build() {
  local value=0
  if [ -f "$STATE_FILE" ]; then
    value=$(tr -d '[:space:]' < "$STATE_FILE")
    case "$value" in
      ""|*[!0-9]*) die "invalid allocator state in $STATE_FILE" ;;
    esac
  fi
  printf '%s' "$value"
}

acquire_allocator_lock() {
  local waited=0
  mkdir -p "$APPSTORE_DIR"
  chmod 700 "$APPSTORE_DIR"
  until shlock -p "$$" -f "$LOCK_FILE"; do
    [ "$waited" -lt 60 ] \
      || die "timed out waiting for the build-number allocator"
    sleep 1
    waited=$((waited + 1))
  done
  LOCK_HELD=true
}

release_allocator_lock() {
  local owner=""
  if [ -f "$LOCK_FILE" ]; then
    owner=$(tr -d '[:space:]' < "$LOCK_FILE")
  fi
  if [ "$owner" = "$$" ]; then
    rm -f -- "$LOCK_FILE"
  fi
  LOCK_HELD=false
}

next_build_number() {
  local remote local_state baseline next tmp
  acquire_allocator_lock
  remote=$(highest_remote_build)
  local_state=$(read_local_build)
  baseline=$PROJECT_BUILD
  if [ "$remote" -gt "$baseline" ]; then baseline=$remote; fi
  if [ "$local_state" -gt "$baseline" ]; then baseline=$local_state; fi
  next=$((baseline + 1))
  [ "$next" -le 9999 ] \
    || die "build number $next exceeds the supported integer range"

  tmp=$(mktemp "${STATE_FILE}.tmp.XXXXXX")
  printf '%s\n' "$next" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$STATE_FILE"
  release_allocator_lock
  BUILD="$next"
}

preview_build_number() {
  local remote local_state baseline
  acquire_allocator_lock
  remote=$(highest_remote_build)
  local_state=$(read_local_build)
  baseline=$PROJECT_BUILD
  if [ "$remote" -gt "$baseline" ]; then baseline=$remote; fi
  if [ "$local_state" -gt "$baseline" ]; then baseline=$local_state; fi
  release_allocator_lock
  REMOTE_BUILD="$remote"
  BUILD="$((baseline + 1))"
}

if [ "$DRY_RUN" = true ]; then
  BUILD=""
  REMOTE_BUILD=""
  preview_build_number
  echo "==> ready: ${BASE_TAG} · ${BRANCH} @ ${COMMIT}"
  echo "==> App Store Connect highest build: ${REMOTE_BUILD}; next would be ${BUILD}"
  echo "==> dry run only; allocator state was not changed"
  exit 0
fi

WORK=$(mktemp -d)
ARCHIVE="$WORK/Alicia.xcarchive"
EXPORT="$WORK/export"
CHECK="$WORK/check"

# The allocator reconciles the project baseline, our last local reservation,
# and App Store Connect under one machine-wide lock. It never edits source.
BUILD=""
if [ "$VERIFY_ONLY" = true ]; then
  REMOTE_BUILD=""
  preview_build_number
else
  next_build_number
fi
echo "==> shipping ${BASE_TAG} · ${BRANCH} @ ${COMMIT} as ${VERSION} (${BUILD})"

echo "==> archiving…"
xcodebuild -scheme Alicia -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" archive -allowProvisioningUpdates -quiet \
  CURRENT_PROJECT_VERSION="$BUILD" \
  ALICIA_BUILD_BRANCH="$BRANCH" \
  ALICIA_BUILD_COMMIT="$COMMIT"

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>teamID</key><string>${ASC_TEAM_ID}</string>
	<key>signingStyle</key><string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>uploadSymbols</key><true/>
	<key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "==> exporting…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -allowProvisioningUpdates -quiet

# Inspect the exact bytes that would be uploaded. These guards catch a source
# plist that was not bundled, a lost build override or branch identity, and a
# development-signed export. No credential is printed.
unzip -qo "$EXPORT/Alicia.ipa" -d "$CHECK"
BUILT_APP="$CHECK/Payload/Alicia.app"
[ -r "$BUILT_APP/Secrets.plist" ] \
  || die "exported app has no Secrets.plist; refusing to upload a mock-backed build"
/usr/libexec/PlistBuddy -c 'Print :BaseURL' "$BUILT_APP/Secrets.plist" >/dev/null 2>&1 \
  || die "exported Secrets.plist is missing BaseURL"
/usr/libexec/PlistBuddy -c 'Print :Token' "$BUILT_APP/Secrets.plist" >/dev/null 2>&1 \
  || die "exported Secrets.plist is missing Token"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILT_APP/Info.plist")" = "$BUILD" ] \
  || die "exported build number does not match allocator reservation"
[ "$(/usr/libexec/PlistBuddy -c 'Print :AliciaBuildBranch' "$BUILT_APP/Info.plist")" = "$BRANCH" ] \
  || die "exported app does not identify its source branch"
SIGNATURE=$(codesign -dvv "$BUILT_APP" 2>&1) \
  || die "could not inspect the exported app signature"
case "$SIGNATURE" in
  *"Apple Distribution"*) ;;
  *) die "IPA is not distribution-signed; refusing to upload" ;;
esac

if [ "$VERIFY_ONLY" = true ]; then
  echo "==> archive verified: build, branch, secret, and distribution signature"
  echo "==> verify only; no build number was reserved and nothing was uploaded"
  exit 0
fi

echo "==> uploading to App Store Connect…"
xcrun altool --upload-package "$EXPORT/Alicia.ipa" --wait \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo
echo "==> ${BASE_TAG} · ${BRANCH} (${VERSION}/${BUILD}) is processed by Apple."
echo "    The repository was not modified; there is no version bump to commit."
