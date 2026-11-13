#!/bin/zsh
# Verifies the signatures and architectures of a built gpsloader.app (used by release.sh, usable alone).
#
# Usage: Scripts/verify-bundle.sh path/to/gpsloader.app [--require-developer-id]
# --require-developer-id (implied for exported builds) is the release mode: it also requires the source code URL.
set -euo pipefail

APP="${1:?usage: verify-bundle.sh path/to/gpsloader.app [--require-developer-id]}"
REQUIRE_DEVELOPER_ID="${2:-}"
[[ -z "${REQUIRE_DEVELOPER_ID}" && "${APP}" == *"/export/"* ]] && REQUIRE_DEVELOPER_ID="--require-developer-id"

fail() { echo "verify-bundle: $1" >&2; exit 1; }

# GPL-3.0-or-later: the app must say where its source code is available (spec app-shell, "Lizenzhinweise").
plist="${APP}/Contents/Info.plist"
source_url=$(/usr/libexec/PlistBuddy -c "Print :GPSLoaderSourceCodeURL" "${plist}" 2>/dev/null) \
    || fail "Info.plist has no GPSLoaderSourceCodeURL"
if [[ "${source_url}" == https://* ]]; then
    echo "ok: source code URL ${source_url}"
elif [[ -n "${REQUIRE_DEVELOPER_ID}" ]]; then
    fail "release build without source code URL (set GPSLOADER_SOURCE_CODE_URL in project.yml to an https URL)"
else
    echo "note: no source code URL set (GPSLOADER_SOURCE_CODE_URL); required for release builds"
fi

codesign --verify --strict --deep "${APP}" || fail "deep signature verification failed"

check() {
    local item="$1" want_runtime="$2" want_archs="$3"
    [[ -e "${item}" ]] || fail "missing ${item}"
    local info
    info=$(codesign -dv --verbose=2 "${item}" 2>&1)
    if [[ -n "${REQUIRE_DEVELOPER_ID}" ]]; then
        grep -q "Authority=Developer ID Application" <<< "${info}" || fail "${item:t} is not signed with Developer ID"
    fi
    grep -q "TeamIdentifier=4TNB35NY7G" <<< "${info}" || fail "${item:t} has the wrong team"
    if [[ "${want_runtime}" == "runtime" ]]; then
        grep -q "flags=.*runtime" <<< "${info}" || fail "${item:t} has no Hardened Runtime"
    fi
    if [[ -n "${want_archs}" ]]; then
        local binary="${item}"
        [[ -d "${item}" ]] && binary="${item}/Contents/MacOS/${item:t:r}"
        local archs
        archs=$(lipo -archs "${binary}")
        [[ "${archs}" == "${want_archs}" ]] || fail "${item:t}: architectures '${archs}', expected '${want_archs}'"
    fi
    echo "ok: ${item#${APP}/}"
}

check "${APP}" runtime "x86_64 arm64"

# No helper programs and no Qt since gpsbabel was removed (change remove-gpsbabel, design D5).
[[ ! -e "${APP}/Contents/Helpers" ]] || fail "unexpected Contents/Helpers (gpsbabel and RosettaInstaller are gone)"
[[ ! -e "${APP}/Contents/Frameworks/QtCoreGpsBabel.framework" ]] || fail "unexpected QtCoreGpsBabel.framework"
echo "ok: no helpers, no Qt"

for license in GPL-3.0 MIT-GPSLoggerKit; do
    [[ -f "${APP}/Contents/Resources/Licenses/${license}.txt" ]] || fail "missing license ${license}"
done
echo "verify-bundle: all checks passed"
