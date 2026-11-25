#!/bin/bash
# Rez custom build command for Tristimulator.
#
# Usage (called by rez-build):
#   bash build.sh          — build only
#   bash build.sh install  — build and install to $REZ_BUILD_INSTALL_PATH
set -euo pipefail

REPO_ROOT="${REZ_BUILD_SOURCE_PATH}"
INSTALL_PATH="${REZ_BUILD_INSTALL_PATH}"
WORK="${REZ_BUILD_PATH}"

# ── 1. Third-party static libraries ────────────────────────────────────────
"${REPO_ROOT}/Scripts/build_thirdparty.sh"

# ── 2. Build with xcodebuild ──────────────────────────────────────────────
DERIVED="${WORK}/DerivedData"
ARCHIVE="${WORK}/Tristimulator.xcarchive"
mkdir -p "${DERIVED}"

THIRDPARTY_PREFIX="${HOME}/Library/Caches/Tristimulator/ThirdParty/installed/arm64-osx-tristimulator"
XCCONFIG="${WORK}/rez-build.xcconfig"

cat > "${XCCONFIG}" <<EOF
HEADER_SEARCH_PATHS = ${THIRDPARTY_PREFIX}/include ${THIRDPARTY_PREFIX}/include/OpenEXR ${THIRDPARTY_PREFIX}/include/Imath
LIBRARY_SEARCH_PATHS = ${THIRDPARTY_PREFIX}/lib
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = -
DEVELOPMENT_TEAM =
CODE_SIGNING_ALLOWED = YES
CODE_SIGNING_REQUIRED = YES
ENABLE_HARDENED_RUNTIME = NO
ENABLE_APP_SANDBOX = NO
PROVISIONING_PROFILE_SPECIFIER =
EOF

# Xcode <27 cannot compile .icon assets (Xcode 27 format). Fall back to the
# legacy AppIcon.appiconset that ships in Assets.xcassets and exclude .icon
# bundles so actool never sees them.
XCODE_MAJOR=$(xcodebuild -version | head -1 | sed 's/Xcode //' | cut -d. -f1)
if [[ "${XCODE_MAJOR}" -lt 27 ]]; then
    cat >> "${XCCONFIG}" <<'COMPAT'
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = NO
EXCLUDED_SOURCE_FILE_NAMES = $(inherited) *.icon
COMPAT
fi

# Append the generated static link flags
GENERATED_XCCONFIG="${REPO_ROOT}/Generated/ThirdParty.generated.xcconfig"
if [[ -f "${GENERATED_XCCONFIG}" ]]; then
    # Extract OTHER_LDFLAGS from the generated file
    # ponytail: grep/sed, not rg/sd — the rez build env has no Homebrew tools
    link_flags=$(grep '^OTHER_LDFLAGS' "${GENERATED_XCCONFIG}" | sed 's/^OTHER_LDFLAGS[[:space:]]*=[[:space:]]*//' || true)
    if [[ -n "${link_flags}" ]]; then
        printf 'OTHER_LDFLAGS = %s\n' "${link_flags}" >> "${XCCONFIG}"
    fi
fi

xcodebuild build \
    -project "${REPO_ROOT}/Tristimulator.xcodeproj" \
    -scheme Tristimulator \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "${DERIVED}" \
    -xcconfig "${XCCONFIG}" \
    CODE_SIGN_IDENTITY="-" \
    ONLY_ACTIVE_ARCH=YES

# ── 3. Install ────────────────────────────────────────────────────────────
if [[ "${1:-}" == "install" ]]; then
    APP_PATH=$(find "${DERIVED}/Build/Products/Release" -maxdepth 4 -type d -name 'Tristimulator.app' | head -1)
    if [[ -z "${APP_PATH}" ]]; then
        echo "ERROR: Tristimulator.app not found in build products" >&2
        exit 1
    fi

    # bin/ — a wrapper script that launches the .app
    mkdir -p "${INSTALL_PATH}/bin"
    cat > "${INSTALL_PATH}/bin/tristimulator" <<'LAUNCHER'
#!/bin/bash
# Launch Tristimulator.app from a rez environment.
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)/Tristimulator.app"
open -a "${APP_DIR}" "$@"
LAUNCHER
    chmod +x "${INSTALL_PATH}/bin/tristimulator"

    # The .app bundle
    cp -a "${APP_PATH}" "${INSTALL_PATH}/Tristimulator.app"

    # Bundled OCIO configs
    mkdir -p "${INSTALL_PATH}/ocio/luts"
    cp "${REPO_ROOT}/OCIO/"*.ocio "${INSTALL_PATH}/ocio/"
    if compgen -G "${REPO_ROOT}/OCIO/luts/*" > /dev/null; then
        cp -a "${REPO_ROOT}/OCIO/luts/"* "${INSTALL_PATH}/ocio/luts/"
    fi

    echo "Installed Tristimulator to ${INSTALL_PATH}"
fi
