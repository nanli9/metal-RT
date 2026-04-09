#!/bin/bash
# Build and run the Metal ray tracer, or run tests.
# Usage:
#   ./run.sh              — build and run the app, console output -> log.txt
#   ./run.sh test-import  — build and run the FBX import test, output -> log.txt
#   ./run.sh test-scene   — build and run the full scene loading test, output -> log.txt
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SCHEME="macOS - Metal3 - SimplePathTracer"
PROJECT="SimplePathTracer.xcodeproj"

COMMON_SRCS="Import/SceneImporter.mm ThirdParty/ufbx/ufbx.c"
COMMON_FLAGS="-std=c++17 -fobjc-arc -O1 -I ThirdParty/ufbx -I ThirdParty/dds_loader -I Import -I Scene"

if [ "$1" = "test-import" ]; then
    echo "Building FBX import test..."
    mkdir -p Tools/build
    clang++ $COMMON_FLAGS \
        Tools/test_import.mm $COMMON_SRCS \
        -framework Foundation \
        -o Tools/build/test_import 2>&1

    FBX_PATH="${2:-$SCRIPT_DIR/Bistro_v5_2/BistroExterior.fbx}"
    echo "Running import test on $FBX_PATH"
    echo "Console output -> log.txt"
    echo "---"
    Tools/build/test_import "$FBX_PATH" 2>&1 | tee log.txt

elif [ "$1" = "test-scene" ]; then
    echo "Building scene loading test..."
    mkdir -p Tools/build
    SCENE_SRCS="Scene/TextureAsset.mm Scene/TextureCache.mm Scene/MaterialAsset.mm Scene/SceneAsset.mm Scene/SceneLoader.mm ThirdParty/dds_loader/DDSLoader.mm"
    clang++ $COMMON_FLAGS \
        Tools/test_scene.mm $COMMON_SRCS $SCENE_SRCS \
        -framework Foundation -framework Metal -framework MetalKit \
        -o Tools/build/test_scene 2>&1

    FBX_PATH="${2:-$SCRIPT_DIR/Bistro_v5_2/BistroExterior.fbx}"
    echo "Running scene test on $FBX_PATH"
    echo "Console output -> log.txt"
    echo "---"
    Tools/build/test_scene "$FBX_PATH" 2>&1 | tee log.txt

else
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
fi
