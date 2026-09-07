#!/usr/bin/env bash
# archive-and-upload.sh — one-command TestFlight build + upload.
#
# Bumps CFBundleVersion in project.yml, regenerates the .xcodeproj, archives in
# Release, exports the IPA, and uploads via `xcrun altool` with an API key.
# Non-interactive: no Xcode UI, no Apple ID password prompts.
#
# Prerequisites (one-time):
#   • App Store Connect API key at ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   • scripts/.env.local with APP_STORE_CONNECT_KEY_ID and _ISSUER_ID (gitignored)
#   • An app record for the bundle ID in App Store Connect. Apple's API cannot
#     create one — /v1/apps allows only GET and UPDATE — so the first one must be
#     added by hand at appstoreconnect.apple.com → Apps → +.
#   • xcodegen on PATH.
#
# Usage:
#   ./scripts/archive-and-upload.sh              # bump + archive + export + upload
#   ./scripts/archive-and-upload.sh --dry-run    # everything except the upload
#   ./scripts/archive-and-upload.sh --skip-bump  # reuse the current CFBundleVersion
set -euo pipefail

DRY_RUN=0
SKIP_BUMP=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=1 ;;
    --skip-bump) SKIP_BUMP=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/.env.local" ] && source "$SCRIPT_DIR/.env.local"
: "${APP_STORE_CONNECT_KEY_ID:?Set APP_STORE_CONNECT_KEY_ID in scripts/.env.local}"
: "${APP_STORE_CONNECT_ISSUER_ID:?Set APP_STORE_CONNECT_ISSUER_ID in scripts/.env.local}"

KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
[ -f "$KEY_FILE" ] || { echo "ERROR: API key not found at $KEY_FILE" >&2; exit 1; }

# ─── 1. Build number ───
CURRENT=$(grep -E '^\s*CURRENT_PROJECT_VERSION: [0-9]+' project.yml | grep -oE '[0-9]+')
[ -n "$CURRENT" ] || { echo "ERROR: no CURRENT_PROJECT_VERSION in project.yml" >&2; exit 1; }
if [ "$SKIP_BUMP" -eq 0 ]; then
  NEXT=$((CURRENT + 1))
  sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )[0-9]+/\1${NEXT}/" project.yml
  echo "▶ bumped build $CURRENT → $NEXT"
else
  NEXT="$CURRENT"
  echo "▶ skip-bump: build stays at $NEXT"
fi
MARKETING=$(grep -E '^\s*MARKETING_VERSION: ' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/')

# ─── 2. Project ───
echo "▶ xcodegen generate"
xcodegen generate >/dev/null

# ─── 3. Archive ───
ARCHIVE="build/RoadApp.xcarchive"
rm -rf build
echo "▶ archiving (Release)"
xcodebuild -project RoadApp.xcodeproj -scheme RoadApp -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_FILE" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
  -quiet archive

# ─── 4. Export ───
# This is also where the Apple Distribution certificate and the App Store
# provisioning profile get minted, which is why the API key is passed here too.
EXPORT_DIR="build/export"
echo "▶ exporting IPA"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_FILE" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
  -quiet

IPA=$(ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1)
[ -f "$IPA" ] || { echo "ERROR: no .ipa produced in $EXPORT_DIR" >&2; exit 1; }
echo "▶ IPA: $IPA ($(du -h "$IPA" | cut -f1))"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "▶ dry-run: not uploading"
  echo "✅ $MARKETING (build $NEXT) ready at $IPA"
  exit 0
fi

# ─── 5. Upload ───
echo "▶ uploading to App Store Connect"
xcrun altool --upload-app --type ios --file "$IPA" \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"

echo ""
echo "✅ uploaded $MARKETING (build $NEXT) — TestFlight processing takes ~5-30 min"
echo "   Attach it to the Internal group when it finishes with:"
echo "     python3 scripts/await-build.py $NEXT"
