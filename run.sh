#!/bin/bash
# Build and run the Metal ray tracer, dumping console output to log.txt
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SCHEME="macOS - Metal3 - SimplePathTracer"
PROJECT="SimplePathTracer.xcodeproj"

echo "Building $SCHEME..."
xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=macOS" \
    build 2>&1 | tail -1

# Find the built app
DERIVED_DATA=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')
APP="$DERIVED_DATA/SimplePathTracer-Metal3.app"

if [ ! -d "$APP" ]; then
    echo "ERROR: App not found at $APP"
    exit 1
fi

EXE="$APP/Contents/MacOS/SimplePathTracer-Metal3"
echo "Running $EXE"
echo "Console output -> log.txt"
echo "---"

# Run the app, capturing stderr (NSLog) to log.txt while also showing it
"$EXE" 2>&1 | tee log.txt
