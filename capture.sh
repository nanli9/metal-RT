#!/bin/bash
# Capture the frontmost app window to screenshot.png
# Usage: ./capture.sh [output_path]
#
# Run the app first, then run this script.
# Claude Code can read the screenshot via: Read screenshot.png

OUTPUT="${1:-screenshot.png}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

sleep 0.5

# Capture the frontmost window (-w = interactive window select, -x = no sound)
# If you want automatic (no click): replace -w with -l <windowID>
screencapture -w -x -t png "$OUTPUT" 2>/dev/null

if [ -f "$OUTPUT" ]; then
    echo "Captured to $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
else
    echo "Capture failed. Make sure the app window is visible."
    exit 1
fi
