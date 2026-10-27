#!/bin/bash
# Code-sign an installed HyperXTalk / OpenXTalk app bundle (e.g. one copied to
# /Applications) using the same recipe as `make compile-mac` in Makefile.Mac.
#
# Usage:
#   tools/sign-mac-app.sh [/path/to/App.app] [entitlements.plist]
#
# Environment:
#   CODESIGN_IDENTITY   Signing identity. Defaults to "-" (ad-hoc). For a
#                       Developer ID build set e.g.
#                       CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#
# Why not `codesign --deep`?  See Makefile.Mac: --deep re-signs every nested
# executable with --options runtime, which on macOS 26+ produces page-hash
# mismatches and SIGKILLs the helper tools.  Instead we sign nested
# dylibs/frameworks inside-out without the hardened runtime, sign loadable
# bundles and loose tools with the runtime, and finally sign only the
# top-level app with runtime + entitlements.  The allow-jit entitlement is
# checked against the calling process, so only the app itself needs it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP="${1:-/Applications/OXT-beyond.app}"
ENTITLEMENTS="${2:-$REPO_ROOT/HyperXTalk.entitlements}"
IDENTITY="${CODESIGN_IDENTITY:--}"

if [ ! -d "$APP" ]; then
  echo "error: app bundle not found: $APP" >&2
  exit 1
fi
if [ ! -f "$ENTITLEMENTS" ]; then
  echo "error: entitlements file not found: $ENTITLEMENTS" >&2
  exit 1
fi

echo "App:          $APP"
echo "Identity:     $IDENTITY"
echo "Entitlements: $ENTITLEMENTS"
echo

# codesign refuses bundles that carry Finder info / resource forks
# ("resource fork, Finder information, or similar detritus not allowed").
# Strip extended attributes first.  This also clears the quarantine flag.
echo "Stripping extended attributes..."
xattr -cr "$APP"

echo "Signing nested frameworks and dylibs (inside-out, no runtime)..."
find "$APP" \( -name "*.framework" -o -name "*.dylib" \) -not -path "*/Contents/Tools/*" \
  | sort -r | while read -r F; do
    codesign --force --sign "$IDENTITY" "$F" 2>/dev/null || true
  done

# External bundles / dylibs (revdb.bundle, revzip.bundle, Tools/Externals/...)
# are dlopen'd into the hardened-runtime process, so on macOS 26+ they must
# carry CS_RUNTIME as well.
echo "Signing loadable bundles and external dylibs (with runtime)..."
find "$APP" \( -name "*.bundle" -o -path "*/Contents/Tools/*.dylib" \) -prune \
  | sort -r | while read -r F; do
    codesign --force --sign "$IDENTITY" --options runtime "$F" 2>/dev/null || true
  done

# Loose standalone tools shipped inside the bundle.  They use libffi/MAP_JIT
# so they need the hardened runtime + allow-jit entitlement to run at all.
echo "Signing standalone tools (runtime + entitlements)..."
for name in server-community lc-compile lc-run lc-compile-ffi-java installer-stub \
            standalone-community; do
  find "$APP" -type f -name "$name" | while read -r F; do
    codesign --force --sign "$IDENTITY" --options runtime \
      --entitlements "$ENTITLEMENTS" "$F" 2>/dev/null || true
  done
done

echo "Signing $(basename "$APP") with Hardened Runtime + entitlements..."
codesign --force --sign "$IDENTITY" --options runtime \
  --entitlements "$ENTITLEMENTS" "$APP"

echo
echo "Verifying..."
codesign --verify --strict --verbose=2 "$APP"
codesign --display --entitlements - "$APP" 2>&1 | grep -q "allow-jit" \
  && echo "allow-jit entitlement present." \
  || echo "warning: allow-jit entitlement NOT found on the app signature." >&2

echo
echo "Done. Launch with: open \"$APP\""
