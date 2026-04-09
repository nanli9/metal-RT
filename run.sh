#!/bin/bash
# Build and run the Metal ray tracer.
#
# Usage:
#   ./run.sh                                — Cornell box (default)
#   ./run.sh cornell-box                    — Cornell box (explicit)
#   ./run.sh path/to/scene.fbx             — load FBX scene
#   ./run.sh Bistro_v5_2/BistroExterior.fbx — load Bistro
#   ./run.sh test-import [path.fbx]         — FBX import test -> log.txt
#   ./run.sh test-scene  [path.fbx]         — scene loading test -> log.txt
#   ./run.sh test-gpu    [path.fbx]         — GPU upload + AS test -> log.txt
#
# All output goes to log.txt.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SCHEME="macOS - Metal3 - SimplePathTracer"
PROJECT="SimplePathTracer.xcodeproj"

COMMON_SRCS="Import/SceneImporter.mm ThirdParty/ufbx/ufbx.c"
COMMON_FLAGS="-std=c++17 -fobjc-arc -O1 -I ThirdParty/ufbx -I ThirdParty/dds_loader -I Import -I Scene -I Renderer -I GPU"

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

elif [ "$1" = "test-gpu" ]; then
    echo "Building GPU upload + AS test..."
    mkdir -p Tools/build
    SCENE_SRCS="Scene/TextureAsset.mm Scene/TextureCache.mm Scene/MaterialAsset.mm Scene/SceneAsset.mm Scene/SceneLoader.mm ThirdParty/dds_loader/DDSLoader.mm"
    GPU_SRCS="GPU/GPUScene.mm GPU/SceneUploader.mm GPU/AccelerationStructureBuilder.mm"
    clang++ $COMMON_FLAGS -I GPU \
        Tools/test_gpu.mm $COMMON_SRCS $SCENE_SRCS $GPU_SRCS \
        -framework Foundation -framework Metal -framework MetalKit \
        -o Tools/build/test_gpu 2>&1

    FBX_PATH="${2:-$SCRIPT_DIR/Bistro_v5_2/BistroExterior.fbx}"
    echo "Running GPU test on $FBX_PATH"
    echo "Console output -> log.txt"
    echo "---"
    Tools/build/test_gpu "$FBX_PATH" 2>&1 | tee log.txt

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

    # Determine scene argument: no arg or "cornell-box" (case-insensitive) = Cornell box
    SCENE_ARG="${1:-cornell-box}"

    # Resolve relative FBX paths to absolute
    if echo "$SCENE_ARG" | grep -iq "^cornell-box$"; then
        echo "Running with Cornell box scene"
        SCENE_ARG="cornell-box"
    else
        # Make path absolute if relative
        if [[ "$SCENE_ARG" != /* ]]; then
            SCENE_ARG="$SCRIPT_DIR/$SCENE_ARG"
        fi
        if [ ! -f "$SCENE_ARG" ]; then
            echo "ERROR: FBX file not found: $SCENE_ARG"
            exit 1
        fi
        echo "Running with scene: $SCENE_ARG"
    fi

    echo "Console output -> log.txt"
    echo "---"

    "$EXE" "$SCENE_ARG" 2>&1 | tee log.txt
fi
