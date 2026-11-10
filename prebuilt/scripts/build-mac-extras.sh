#!/bin/bash
#
# build-mac-extras.sh — populate the macOS prebuilt/ tree with the bits
# that BUILD1.md + the existing prebuilt/scripts scripts don't cover.
#
# Run this AFTER build-libffi-mac-arm64.sh and build-libz-mac-arm64.sh, and
# BEFORE build-libcairo-mac-arm64.sh — cairo is configured to link the
# libpng.a that this script produces.  See the prebuilt-mac step order in
# Makefile.Mac.
#
# Then this script:
#   - Builds libgif/libjpeg/libpng/libpcre via xcodebuild and installs them
#   - Builds libcustomcrypto.a / libcustomssl.a from the OpenSSL source via
#     build-openssl.sh (configured with no-module so the legacy provider is
#     compiled into libcrypto.a; engine targets the 3.x symbol names directly)
#   - Writes empty stub libpq.a and libmysql.a so the dbpostgresql /
#     dbmysql externals can link via -undefined dynamic_lookup
#
# Requirements: Xcode command line tools and Homebrew (for the other
# prebuilt-mac steps); network access the first time, to fetch the OpenSSL
# source tarball.
#
# All of this is a workaround for the broken fetch-mac step in the
# generated Xcode project. Once gyp is usable again or the prebuilt
# tarballs are re-hosted, this script can go away.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${REPO_ROOT}"

PREBUILT_LIB="${REPO_ROOT}/prebuilt/lib/mac"
DEBUG_OUT="${REPO_ROOT}/_build/mac/Debug"

mkdir -p "${PREBUILT_LIB}"

# ── 1. Extra thirdparty libs via xcodebuild ──────────────────────────────────
echo "=== Building libgif libjpeg libpng libpcre ==="
for LIB in libgif libjpeg libpng libpcre; do
    xcodebuild \
        -project "${REPO_ROOT}/build-mac/hyperxtalk/thirdparty/${LIB}/${LIB}.xcodeproj" \
        -configuration Debug \
        -arch arm64 \
        SOLUTION_DIR="${REPO_ROOT}" \
        2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" || true
    if [ ! -f "${DEBUG_OUT}/${LIB}.a" ]; then
        echo "ERROR: ${LIB}.a missing after xcodebuild"
        exit 1
    fi
    cp "${DEBUG_OUT}/${LIB}.a" "${PREBUILT_LIB}/${LIB}.a"
done

# ── 2. libcustomcrypto / libcustomssl from an OpenSSL no-module build ────────
# Do NOT take these from Homebrew's openssl@3. Homebrew builds OpenSSL 3
# with loadable provider modules: the legacy provider (Blowfish, RC4, DES,
# CAST5, IDEA, MD4, RIPEMD160, ...) is a separate legacy.dylib under
# /opt/homebrew/Cellar/openssl@3/<version>/lib/ossl-modules, and that
# absolute path is baked into libcrypto.a as MODULESDIR. An engine linked
# against that archive only finds the legacy provider on a Mac that has the
# very same Homebrew openssl@3 version installed; on every other Mac
# OSSL_PROVIDER_load(NULL, "legacy") fails and `encrypt ... using "blowfish"`
# returns empty with an SSL "could not load the shared library" error
# (GitHub issue #398). build-openssl.sh configures OpenSSL 3.x with
# no-module, which compiles the default and legacy providers into
# libcrypto.a itself, so the shipped engine is self-contained.
echo "=== Building OpenSSL (no-module) for libcustomcrypto/libcustomssl ==="
OPENSSL_BUILDDIR="${REPO_ROOT}/prebuilt/build"
OPENSSL_INSTALL_DIR="${OPENSSL_BUILDDIR}/install"
# build-openssl.sh also copies the headers into ${OUTPUT_DIR}/include; stage
# them out of the tree so the tracked prebuilt/include/openssl is untouched.
OPENSSL_STAGE_DIR="${OPENSSL_BUILDDIR}/openssl-stage"
mkdir -p "${OPENSSL_BUILDDIR}" "${OPENSSL_INSTALL_DIR}" "${OPENSSL_STAGE_DIR}"
(
    cd "${REPO_ROOT}/prebuilt" && \
    BASEDIR="${REPO_ROOT}/prebuilt" \
    BUILDDIR="${OPENSSL_BUILDDIR}" \
    INSTALL_DIR="${OPENSSL_INSTALL_DIR}" \
    OUTPUT_DIR="${OPENSSL_STAGE_DIR}" \
    PLATFORM=mac ARCH=arm64 SUBPLATFORM= \
    bash scripts/build-openssl.sh
)
OPENSSL_LIB="${OPENSSL_INSTALL_DIR}/mac/arm64/lib"
if [ ! -f "${OPENSSL_LIB}/libcrypto.a" ] || [ ! -f "${OPENSSL_LIB}/libssl.a" ]; then
    echo "ERROR: OpenSSL build did not produce ${OPENSSL_LIB}/libcrypto.a"
    exit 1
fi
# A previous run may have left read-only copies (Homebrew's archives are
# installed read-only); `cp -f` replaces them and chmod keeps ours writable.
cp -f "${OPENSSL_LIB}/libcrypto.a" "${PREBUILT_LIB}/libcustomcrypto.a"
cp -f "${OPENSSL_LIB}/libssl.a"    "${PREBUILT_LIB}/libcustomssl.a"
chmod u+w "${PREBUILT_LIB}/libcustomcrypto.a" "${PREBUILT_LIB}/libcustomssl.a"
if ! nm "${PREBUILT_LIB}/libcustomcrypto.a" 2>/dev/null | grep -q "ossl_legacy_provider_init"; then
    echo "ERROR: libcustomcrypto.a has no built-in legacy provider (was OpenSSL configured with no-module?)"
    exit 1
fi

# ── 3. Stub libpq.a and libmysql.a ───────────────────────────────────────────
# dbpostgresql.bundle and dbmysql.dylib link with -undefined dynamic_lookup
# so unresolved symbols are deferred to load time. The linker still insists
# on being able to find -lpq and -lmysql as files, so provide minimal
# archives with a single dummy object. Runtime will fail if you actually
# use these database drivers — install real libpq / libmysqlclient and
# replace these if you need that functionality.
echo "=== Creating stub libpq.a and libmysql.a ==="
STUB_DIR="/tmp/hxt-mac-extras"
mkdir -p "${STUB_DIR}"
STUB_C="${STUB_DIR}/db-driver-stub.c"
cat > "${STUB_C}" <<'EOF'
/* Stub archive marker for dbpostgresql / dbmysql link-time satisfaction.
 * These drivers actually resolve symbols at dlopen time; see
 * prebuilt/scripts/build-mac-extras.sh for context. */
int _hxt_db_driver_stub(void) { return 0; }
EOF
STUB_O="${STUB_DIR}/db-driver-stub.o"
clang -arch arm64 -c "${STUB_C}" -o "${STUB_O}"
ar rcs "${PREBUILT_LIB}/libpq.a"    "${STUB_O}"
ar rcs "${PREBUILT_LIB}/libmysql.a" "${STUB_O}"

echo ""
echo "=== Done. prebuilt/lib/mac now has: ==="
ls "${PREBUILT_LIB}/" | sort
