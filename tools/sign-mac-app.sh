#!/bin/bash
# sign-mac-app.sh — code-sign any macOS app bundle the way HyperXTalk /
# OpenXTalk needs it (hardened runtime + JIT entitlements on the app, nested
# code signed inside-out, no --deep).
#
# This script is self-contained: the default entitlements are embedded below,
# so it can be copied anywhere (e.g. ~/bin) and used on any app.
#
# Usage:
#   sign-mac-app.sh <App.app> [options]
#
# Options:
#   -i, --identity ID        Signing identity (default: "-" = ad-hoc, or
#                            $CODESIGN_IDENTITY if set). For Developer ID:
#                            -i "Developer ID Application: Name (TEAMID)"
#   -e, --entitlements FILE  Use this entitlements plist instead of the
#                            embedded default.
#   -q, --quiet              Only print errors and the final result.
#   -h, --help               Show this help.
#
# Why not `codesign --deep`?  --deep re-signs every nested executable with
# --options runtime, which on macOS 26+ produces page-hash mismatches and
# SIGKILLs helper tools (CODESIGNING, Code 2, Invalid Page).  Instead we:
#   1. sign nested dylibs/frameworks inside-out WITHOUT the hardened runtime,
#   2. sign loadable bundles / plug-in dylibs and standalone tools WITH it,
#   3. sign only the top-level app with runtime + entitlements.
# The allow-jit entitlement is checked against the calling process, so only
# the app itself needs it.

set -euo pipefail

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }

APP=""
ENTITLEMENTS=""
IDENTITY="${CODESIGN_IDENTITY:--}"
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    -i|--identity)     IDENTITY="$2"; shift 2 ;;
    -e|--entitlements) ENTITLEMENTS="$2"; shift 2 ;;
    -q|--quiet)        QUIET=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    -*)                echo "error: unknown option $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -z "$APP" ]; then APP="$1"
      elif [ -z "$ENTITLEMENTS" ]; then ENTITLEMENTS="$1"   # legacy 2nd positional
      else echo "error: unexpected argument $1" >&2; exit 2; fi
      shift ;;
  esac
done

if [ -z "$APP" ]; then usage >&2; exit 2; fi
APP="${APP%/}"
if [ ! -d "$APP" ] || [ ! -d "$APP/Contents" ]; then
  echo "error: not an app bundle: $APP" >&2
  exit 1
fi

log() { [ "$QUIET" -eq 1 ] || echo "$@"; }

# ---------------------------------------------------------------------------
# Default entitlements (identical to HyperXTalk.entitlements in the repo).
# ---------------------------------------------------------------------------
TMP_ENT=""
cleanup() { [ -n "$TMP_ENT" ] && rm -f "$TMP_ENT"; }
trap cleanup EXIT

if [ -z "$ENTITLEMENTS" ]; then
  TMP_ENT="$(mktemp -t sign-mac-app-entitlements).plist"
  ENTITLEMENTS="$TMP_ENT"
  cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
	<true/>
	<key>com.apple.security.cs.allow-dyld-environment-variables</key>
	<true/>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
	<key>com.apple.security.cs.disable-executable-page-protection</key>
	<true/>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.device.camera</key>
	<true/>
	<key>com.apple.security.personal-information.location</key>
	<true/>
	<key>com.apple.security.personal-information.addressbook</key>
	<true/>
	<key>com.apple.security.personal-information.photos-library</key>
	<true/>
	<key>com.apple.security.automation.apple-events</key>
	<true/>
	<key>com.apple.security.files.user-selected.executable</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
</dict>
</plist>
PLIST
elif [ ! -f "$ENTITLEMENTS" ]; then
  echo "error: entitlements file not found: $ENTITLEMENTS" >&2
  exit 1
fi

log "App:          $APP"
log "Identity:     $IDENTITY"
log "Entitlements: ${TMP_ENT:+(embedded default)}${TMP_ENT:-$ENTITLEMENTS}"
log

# codesign refuses bundles that carry Finder info / resource forks
# ("resource fork, Finder information, or similar detritus not allowed").
# Strip extended attributes first.  This also clears the quarantine flag.
log "Stripping extended attributes..."
xattr -cr "$APP"

log "Signing nested frameworks and dylibs (inside-out, no runtime)..."
find "$APP" \( -name "*.framework" -o -name "*.dylib" \) \
     -not -path "*/Contents/Tools/*" -not -path "*.bundle/*" \
  | sort -r | while read -r F; do
    codesign --force --sign "$IDENTITY" "$F" 2>/dev/null || true
  done

# Loadable bundles and plug-in dylibs are dlopen'd into the hardened-runtime
# process, so on macOS 26+ they must carry CS_RUNTIME as well.
log "Signing loadable bundles and plug-in dylibs (with runtime)..."
find "$APP" \( -name "*.bundle" -o -path "*/Contents/Tools/*.dylib" \) -prune \
  | sort -r | while read -r F; do
    codesign --force --sign "$IDENTITY" --options runtime "$F" 2>/dev/null || true
  done

# Standalone helper executables shipped inside the bundle (anything in a
# MacOS/ or Tools/ dir that is a Mach-O executable and not the main binary).
# They may use libffi/MAP_JIT, so they need runtime + the JIT entitlement.
MAIN_BIN="$APP/Contents/MacOS/$(defaults read "$APP/Contents/Info" CFBundleExecutable 2>/dev/null || basename "$APP" .app)"
log "Signing standalone helper executables (runtime + entitlements)..."
find "$APP" -type f -perm -u+x \
     \( -path "*/Contents/MacOS/*" -o -path "*/Contents/Tools/*" -o -path "*/Contents/Helpers/*" \) \
     -not -path "*.bundle/*" -not -path "*.framework/*" -not -path "*.app/Contents/*/*.app/*" \
  | while read -r F; do
    [ "$F" = "$MAIN_BIN" ] && continue
    case "$(file -b "$F" 2>/dev/null)" in
      *Mach-O*executable*)
        codesign --force --sign "$IDENTITY" --options runtime \
          --entitlements "$ENTITLEMENTS" "$F" 2>/dev/null || true ;;
    esac
  done

log "Signing $(basename "$APP") with Hardened Runtime + entitlements..."
codesign --force --sign "$IDENTITY" --options runtime \
  --entitlements "$ENTITLEMENTS" "$APP"

log
log "Verifying..."
if [ "$QUIET" -eq 1 ]; then
  codesign --verify --strict "$APP"
else
  codesign --verify --strict --verbose=2 "$APP"
fi
if codesign --display --entitlements - "$APP" 2>&1 | grep -q "allow-jit"; then
  log "allow-jit entitlement present."
else
  echo "warning: allow-jit entitlement NOT found on the app signature." >&2
fi

echo "Signed OK: $APP"
