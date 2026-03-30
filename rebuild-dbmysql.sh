#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Building dbmysql.bundle ==="
xcodebuild \
  -project build-mac/livecode/revdb/revdb.xcodeproj \
  -target dbmysql \
  -configuration Release \
  2>&1 | tail -20

# Find the built bundle
BUILT=$(find _build/mac/Release -name "dbmysql.bundle" -type d 2>/dev/null | head -1)
if [ -z "$BUILT" ]; then
  echo "ERROR: Could not find built dbmysql.bundle"
  echo "Search paths tried: _build/mac/Release/"
  exit 1
fi
echo "Built: $BUILT"

# Verify it contains our fix (will print 'HXT: Unable to load SSL library' if new code)
strings "$BUILT/Contents/MacOS/dbmysql" | grep "HXT:" && echo "✓ New binary confirmed" || echo "✗ WARNING: fix marker not found — old binary may have been linked"

echo "=== Deploying to mac-bin ==="
DRIVERS="mac-bin/HyperXTalk.app/Contents/Tools/Externals/Database Drivers"
RT_DRIVERS="mac-bin/HyperXTalk.app/Contents/Tools/Runtime/Mac OS X/arm64/Externals/Database Drivers"

# Use ditto — unlike cp -R, ditto replaces existing directories rather than nesting
ditto "$BUILT" "mac-bin/dbmysql.bundle"
ditto "$BUILT" "$DRIVERS/dbmysql.bundle"
ditto "$BUILT" "$RT_DRIVERS/dbmysql.bundle"

echo "=== Verify deployed binary ==="
strings "$DRIVERS/dbmysql.bundle/Contents/MacOS/dbmysql" | grep "HXT:" && echo "✓ Deploy confirmed" || echo "✗ Deploy may have failed"

echo "Done."