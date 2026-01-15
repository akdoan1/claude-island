#!/bin/bash
# Build and run Claude Island debug build
# Usage: scripts/dev-build.sh [--no-run]

set -e

cd "$(dirname "$0")/.."

# Get git commit info for version display
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
DIRTY=$(git diff --quiet HEAD 2>/dev/null && echo "" || echo "-dirty")
GIT_COMMIT="${COMMIT}${DIRTY}"

echo "Building Claude Island ($GIT_COMMIT)..."
xcodebuild -scheme ClaudeIsland -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  GIT_COMMIT="$GIT_COMMIT" \
  2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" || true

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

echo "Build succeeded!"

# Skip launch if --no-run flag
if [ "$1" = "--no-run" ]; then
    exit 0
fi

# Find the built app in DerivedData
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Debug -name "Claude Island.app" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built app in DerivedData"
    exit 1
fi

echo "Stopping existing instance..."
pkill -f "Claude Island" 2>/dev/null || true
sleep 0.5

echo "Launching: $APP_PATH"
open "$APP_PATH"
echo "Done!"
