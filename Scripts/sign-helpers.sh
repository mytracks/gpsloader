#!/bin/zsh
# Xcode build phase: re-sign the bundled gpsbabel with Hardened Runtime.
#
# "Code Sign On Copy" preserves the flags of the original signature, which has no
# Hardened Runtime; notarization requires it. This runs after the copy phases and
# before Xcode signs the app itself.
set -euo pipefail

helpers="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
framework="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Frameworks/QtCoreGpsBabel.framework"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[[ -z "${identity}" ]] && identity="-"

timestamp="--timestamp=none"
if [[ "${CONFIGURATION}" == "Release" && "${identity}" != "-" ]]; then
    timestamp="--timestamp"
fi

# Frameworks first (inside out), then the executable that loads them.
codesign --force --sign "${identity}" ${timestamp} "${framework}"
codesign --force --sign "${identity}" ${timestamp} --options runtime "${helpers}/gpsbabel"

codesign --verify --strict "${framework}"
codesign --verify --strict "${helpers}/gpsbabel"
echo "sign-helpers: signed gpsbabel and QtCoreGpsBabel with '${identity}'"
