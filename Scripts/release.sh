#!/bin/zsh
# Builds, signs (Developer ID), notarizes and staples myTracks Loader and packs the ZIP for users (design.md D10).
#
# Usage:
#   Scripts/release.sh [--publish [--dry-run]] [--skip-notarize] [--allow-unpublished] [--profile <name>]
#
#   --publish            after a successful notarization: Git tag <version>, push of the tag and a GitHub release
#                        with release notes (docs/releases/<version>.md), the ZIP and its checksum; pre-release
#                        below 1.0.0 (spec release-publishing, "GitHub-Release der App"). Not with --skip-notarize
#                        or --allow-unpublished.
#   --dry-run            with --publish: print the tag and release commands instead of running them; may then be
#                        combined with --skip-notarize and --allow-unpublished to test the script
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
# Output: build/release/myTracks-Loader-<version>.zip (notarized and stapled unless --skip-notarize)
#         and myTracks-Loader-<version>.zip.sha256. Hyphens, because GitHub turns spaces in asset names into dots.
set -euo pipefail

TEAM_ID="4TNB35NY7G"
PROFILE="gpsloader-notary"
KEY_DIRECTORY="${HOME}/.appstoreconnect/private_keys"
# The issuer of the team's App Store Connect API keys (same as in myTracksNeo); not secret, it only names the team.
DEFAULT_ISSUER_ID="69a6de70-16e7-47e3-e053-5b8c7c11a4d1"
SKIP_NOTARIZE=0
ALLOW_UNPUBLISHED=0
PUBLISH=0
DRY_RUN=0

while (( $# > 0 )); do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        --allow-unpublished) ALLOW_UNPUBLISHED=1 ;;
        --publish) PUBLISH=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --profile) shift; PROFILE="${1:?--profile needs a name}" ;;
        -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

ROOT="${0:A:h:h}"
BUILD="${ROOT}/build/release"
ARCHIVE="${BUILD}/gpsloader.xcarchive"
EXPORT="${BUILD}/export"
APP_NAME="myTracks Loader"
FILE_STEM="myTracks-Loader"
APP="${EXPORT}/${APP_NAME}.app"

step() { print -P "%F{cyan}==> $1%f"; }
fail() { print -P "%F{red}release: $1%f" >&2; exit 1; }

cd "${ROOT}"
run() {
    if (( DRY_RUN )); then print -r -- "would run: ${(q)@}"; else "$@"; fi
}

# --- Checks before the long build -------------------------------------------------------------------------

(( DRY_RUN && ! PUBLISH )) && fail "--dry-run only works with --publish"
if (( PUBLISH && ! DRY_RUN && (SKIP_NOTARIZE || ALLOW_UNPUBLISHED) )); then
    fail "--publish needs a notarized build of a published commit (no --skip-notarize, no --allow-unpublished)"
fi

if (( PUBLISH )); then
    # The version is checked before the build, so that a taken version does not fail after notarization.
    VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}/\1/p' project.yml | head -1)
    [[ "${VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "no MARKETING_VERSION x.y.z in project.yml"
    NOTES="docs/releases/${VERSION}.md"
    step "Checking that ${APP_NAME} ${VERSION} can be published"
    [[ -f "${NOTES}" ]] || fail "missing release notes ${NOTES}"
    git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null && fail "tag ${VERSION} exists already"
    [[ -z "$(git ls-remote --tags origin "refs/tags/${VERSION}")" ]] || fail "tag ${VERSION} exists on origin"
    gh auth status >/dev/null 2>&1 || fail "gh is not signed in"
    gh release view "${VERSION}" >/dev/null 2>&1 && fail "a GitHub release ${VERSION} exists already"
    echo "ok: no tag or release ${VERSION} yet, release notes ${NOTES}"
fi

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
# Fixed package versions (spec release-publishing, "Pakete in der App per Version"; design D3): XcodeGen writes no
# Package.resolved, so the versioned one of GPSLoaderKit is copied in and the build may use nothing else.
RESOLVED="${ROOT}/Packages/GPSLoaderKit/Package.resolved"
[[ -f "${RESOLVED}" ]] || fail "missing ${RESOLVED}"
SWIFTPM="${ROOT}/gpsloader.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "${SWIFTPM}"
cp "${RESOLVED}" "${SWIFTPM}/Package.resolved"

step "Archiving (Release, universal)"
xcodebuild archive \
    -project gpsloader.xcodeproj \
    -scheme gpsloader \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "${ARCHIVE}" \
    -onlyUsePackageVersionsFromResolvedFile \
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

BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP}/Contents/Info.plist")
if (( PUBLISH )); then
    [[ "${BUNDLE_VERSION}" == "${VERSION}" ]] || fail "bundle version ${BUNDLE_VERSION} differs from project.yml (${VERSION})"
fi
VERSION="${BUNDLE_VERSION}"
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP}/Contents/Info.plist")
ZIP="${BUILD}/${FILE_STEM}-${VERSION}.zip"
UPLOAD="${BUILD}/${FILE_STEM}-${VERSION}-notarization.zip"
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

# --- GitHub release ---------------------------------------------------------------------------------------

if (( PUBLISH )); then
    PRERELEASE=()
    [[ "${VERSION}" == 0.* ]] && PRERELEASE=(--prerelease)
    step "Publishing ${APP_NAME} ${VERSION} on GitHub"
    run git tag -a "${VERSION}" -m "${APP_NAME} ${VERSION}"
    run git push origin "${VERSION}"
    run gh release create "${VERSION}" "${ZIP}" "${ZIP}.sha256" --verify-tag --title "${APP_NAME} ${VERSION}" \
        --notes-file "${NOTES}" "${PRERELEASE[@]}"
    if (( DRY_RUN )); then echo "Dry run: nothing was tagged or published."; else echo "Published ${APP_NAME} ${VERSION}."; fi
fi
