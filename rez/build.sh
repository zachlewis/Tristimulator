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

# Append the generated static link flags
GENERATED_XCCONFIG="${REPO_ROOT}/Generated/ThirdParty.generated.xcconfig"
if [[ -f "${GENERATED_XCCONFIG}" ]]; then
    # Extract OTHER_LDFLAGS from the generated file
    link_flags=$(rg '^OTHER_LDFLAGS' "${GENERATED_XCCONFIG}" | sd '^OTHER_LDFLAGS\s*=\s*' '' || true)
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
    APP_PATH=$(fd -t d -d 4 'Tristimulator.app' "${DERIVED}/Build/Products/Release" | head -1)
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
