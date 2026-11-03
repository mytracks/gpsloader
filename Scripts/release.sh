#!/bin/zsh
# Builds, signs (Developer ID), notarizes and staples gpsloader (design.md D10).
#
# Usage:
#   Scripts/release.sh [--skip-notarize] [--profile <notarytool keychain profile>]
#
# One-time setup of the notarization profile (developer, see README.md):
#   xcrun notarytool store-credentials gpsloader-notary --apple-id <id> --team-id 4TNB35NY7G
#
# Output: build/release/gpsloader-<version>.zip (notarized and stapled unless --skip-notarize).
set -euo pipefail

TEAM_ID="4TNB35NY7G"
PROFILE="gpsloader-notary"
SKIP_NOTARIZE=0

while (( $# > 0 )); do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        --profile) shift; PROFILE="$1" ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

ROOT="${0:A:h:h}"
BUILD="${ROOT}/build/release"
ARCHIVE="${BUILD}/gpsloader.xcarchive"
EXPORT="${BUILD}/export"
APP="${EXPORT}/gpsloader.app"

step() { print -P "%F{cyan}==> $1%f"; }

cd "${ROOT}"
mkdir -p "${BUILD}"
# Start from a clean export directory (only inside build/release).
[[ -d "${EXPORT}" ]] && rm -r -- "${EXPORT}"
[[ -d "${ARCHIVE}" ]] && rm -r -- "${ARCHIVE}"

step "Generating Xcode project"
xcodegen generate --quiet

step "Archiving (Release, universal)"
xcodebuild archive \
    -project gpsloader.xcodeproj \
    -scheme gpsloader \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "${ARCHIVE}" \
    -quiet

step "Exporting with Developer ID"
cat > "${BUILD}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE}" \
    -exportPath "${EXPORT}" \
    -exportOptionsPlist "${BUILD}/ExportOptions.plist" \
    -quiet

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP}/Contents/Info.plist")
ZIP="${BUILD}/gpsloader-${VERSION}.zip"

step "Verifying signatures"
"${ROOT}/Scripts/verify-bundle.sh" "${APP}"

step "Creating ${ZIP:t}"
[[ -f "${ZIP}" ]] && rm -- "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"

if (( SKIP_NOTARIZE )); then
    step "Skipping notarization (--skip-notarize)"
    echo "Signed, not notarized: ${ZIP}"
    exit 0
fi

step "Notarizing (profile ${PROFILE})"
xcrun notarytool submit "${ZIP}" --keychain-profile "${PROFILE}" --wait

step "Stapling"
xcrun stapler staple "${APP}"
rm -- "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"

step "Gatekeeper assessment"
spctl --assess --type execute -vv "${APP}"

echo "Done: ${ZIP}"
