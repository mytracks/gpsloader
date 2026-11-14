#!/bin/zsh
# Builds, signs (Developer ID), notarizes and staples gpsloader and packs the ZIP for users (design.md D10).
#
# Usage:
#   Scripts/release.sh [--skip-notarize] [--allow-unpublished] [--profile <notarytool keychain profile>]
#
#   --skip-notarize      only a signed ZIP (for own tests, not for users)
#   --allow-unpublished  skip the check that the commit is clean and pushed to origin
#   --profile            notarytool keychain profile (default gpsloader-notary), used without an API key
#
# Notarization signs in like in myTracksNeo (scripts/notarize-mac.sh): with the App Store Connect API key
# ~/.appstoreconnect/private_keys/app-manager_<key id>.p8 and the team's issuer ID (NOTARY_ISSUER_ID, else the
# file ~/.appstoreconnect/issuer_id, else the issuer of team 4TNB35NY7G below). Without such a key it uses the
# keychain profile, created once with:
#   xcrun notarytool store-credentials gpsloader-notary --apple-id <id> --team-id 4TNB35NY7G
#
# Output: build/release/gpsloader-<version>.zip (notarized and stapled unless --skip-notarize)
#         and gpsloader-<version>.zip.sha256.
set -euo pipefail

TEAM_ID="4TNB35NY7G"
PROFILE="gpsloader-notary"
KEY_DIRECTORY="${HOME}/.appstoreconnect/private_keys"
# The issuer of the team's App Store Connect API keys (same as in myTracksNeo); not secret, it only names the team.
DEFAULT_ISSUER_ID="69a6de70-16e7-47e3-e053-5b8c7c11a4d1"
SKIP_NOTARIZE=0
ALLOW_UNPUBLISHED=0

while (( $# > 0 )); do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        --allow-unpublished) ALLOW_UNPUBLISHED=1 ;;
        --profile) shift; PROFILE="${1:?--profile needs a name}" ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
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
fail() { print -P "%F{red}release: $1%f" >&2; exit 1; }

cd "${ROOT}"

# --- Checks before the long build -------------------------------------------------------------------------

if (( ! SKIP_NOTARIZE && ! ALLOW_UNPUBLISHED )); then
    # GPL-3.0-or-later: the source of every released version is public (openspec/config.yaml).
    step "Checking that the release commit is published"
    [[ -z "$(git status --porcelain)" ]] \
        || fail "uncommitted changes; commit and push first (or --allow-unpublished)"
    git fetch --quiet origin
    git merge-base --is-ancestor HEAD "origin/$(git rev-parse --abbrev-ref HEAD)" 2>/dev/null \
        || fail "HEAD $(git rev-parse --short HEAD) is not pushed to origin (or --allow-unpublished)"
    echo "ok: $(git rev-parse --short HEAD) is on origin"
fi

CREDENTIALS=()
if (( ! SKIP_NOTARIZE )); then
    step "Checking notarization credentials"
    KEY_FILE=$(ls "${KEY_DIRECTORY}"/app-manager*.p8(N) 2>/dev/null | head -1)
    if [[ -n "${KEY_FILE}" ]]; then
        KEY_ID="${${KEY_FILE:t:r}##*_}"   # "app-manager_ABC123.p8" -> "ABC123"
        ISSUER="${NOTARY_ISSUER_ID:-}"
        if [[ -z "${ISSUER}" && -f "${HOME}/.appstoreconnect/issuer_id" ]]; then
            ISSUER=$(tr -d '[:space:]' < "${HOME}/.appstoreconnect/issuer_id")
        fi
        CREDENTIALS=(--key "${KEY_FILE}" --key-id "${KEY_ID}" --issuer "${ISSUER:-${DEFAULT_ISSUER_ID}}")
        DESCRIPTION="API key ${KEY_ID}"
    else
        CREDENTIALS=(--keychain-profile "${PROFILE}")
        DESCRIPTION="keychain profile ${PROFILE}"
    fi
    xcrun notarytool history "${CREDENTIALS[@]}" >/dev/null 2>&1 \
        || fail "notarytool cannot sign in with ${DESCRIPTION}. Add an app-manager API key to ${KEY_DIRECTORY}
  or create the keychain profile once with:
  xcrun notarytool store-credentials ${PROFILE} --apple-id <Apple-ID> --team-id ${TEAM_ID}"
    echo "ok: ${DESCRIPTION}"
fi

security find-identity -v -p codesigning | grep -q "Developer ID Application: .*(${TEAM_ID})" \
    || fail "no 'Developer ID Application' certificate of team ${TEAM_ID} in the keychain"

# --- Build ------------------------------------------------------------------------------------------------

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
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP}/Contents/Info.plist")
ZIP="${BUILD}/gpsloader-${VERSION}.zip"
UPLOAD="${BUILD}/gpsloader-${VERSION}-notarization.zip"
[[ -f "${ZIP}" ]] && rm -- "${ZIP}"
[[ -f "${ZIP}.sha256" ]] && rm -- "${ZIP}.sha256"
[[ -f "${UPLOAD}" ]] && rm -- "${UPLOAD}"

step "Verifying signatures"
"${ROOT}/Scripts/verify-bundle.sh" "${APP}"
# Notarization rejects a debug entitlement and a missing secure timestamp. The output is read first: with
# pipefail, "codesign | grep -q" fails when grep stops early.
ENTITLEMENTS=$(codesign -d --entitlements - --xml "${APP}" 2>/dev/null || true)
[[ "${ENTITLEMENTS}" != *get-task-allow* ]] || fail "the app carries get-task-allow, which notarization rejects"
SIGNATURE=$(codesign -dv --verbose=2 "${APP}" 2>&1)
[[ "${SIGNATURE}" == *$'\nTimestamp='* ]] || fail "the signature has no secure timestamp"
echo "ok: no get-task-allow, secure timestamp"

# --- Notarization -----------------------------------------------------------------------------------------

if (( SKIP_NOTARIZE )); then
    step "Skipping notarization (--skip-notarize)"
else
    step "Submitting to Apple for notarization (${DESCRIPTION}, this takes a few minutes)"
    ditto -c -k --keepParent "${APP}" "${UPLOAD}"
    RESULT="${BUILD}/notarization-result.json"
    xcrun notarytool submit "${UPLOAD}" "${CREDENTIALS[@]}" --wait --output-format json \
        > "${RESULT}" || true
    STATUS=$(plutil -extract status raw -o - "${RESULT}" 2>/dev/null || echo "unknown")
    SUBMISSION=$(plutil -extract id raw -o - "${RESULT}" 2>/dev/null || echo "")
    echo "status: ${STATUS} (submission ${SUBMISSION:-?})"
    if [[ "${STATUS}" != "Accepted" ]]; then
        if [[ -n "${SUBMISSION}" ]]; then
            xcrun notarytool log "${SUBMISSION}" "${CREDENTIALS[@]}" "${BUILD}/notarization-log.json" \
                >/dev/null 2>&1 || true
            fail "notarization ${STATUS}; Apple's log: ${BUILD}/notarization-log.json"
        fi
        fail "notarization failed; output: ${RESULT}"
    fi
    rm -- "${UPLOAD}"

    step "Stapling the ticket"
    xcrun stapler staple -q "${APP}"
    xcrun stapler validate -q "${APP}"

    step "Gatekeeper assessment"
    spctl --assess --type execute -vv "${APP}"
fi

# --- ZIP for users ----------------------------------------------------------------------------------------

step "Creating ${ZIP:t}"
# ditto keeps the stapled ticket, extended attributes and symlinks of the bundle.
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"
(cd "${BUILD}" && shasum -a 256 "${ZIP:t}" > "${ZIP:t}.sha256")

echo
if (( SKIP_NOTARIZE )); then
    echo "Signed, NOT notarized (do not give to users): ${ZIP}"
else
    echo "Ready for users: ${ZIP}"
fi
echo "Version ${VERSION} (${BUILD_NUMBER}), commit $(git rev-parse --short HEAD)"
cat "${ZIP}.sha256"
