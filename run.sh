#!/bin/bash
# Build and run the Metal ray tracer.
#
# Usage:
#   ./run.sh                                — Cornell box (default)
#   ./run.sh cornell-box                    — Cornell box (explicit)
#   ./run.sh path/to/scene.fbx             — load FBX scene
#   ./run.sh a.fbx b.fbx c.fbx            — load + merge multiple FBX files
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

COMMON_SRCS="Import/SceneImporter.mm Import/ImportedSceneMerge.cpp ThirdParty/ufbx/ufbx.c"
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

    # Collect scene arguments: no args or "cornell-box" = Cornell box
    # Multiple FBX paths are resolved and passed through
    SCENE_ARGS=()
    for arg in "$@"; do
        if echo "$arg" | grep -iq "^cornell-box$"; then
            SCENE_ARGS=("cornell-box")
            break
        fi
        # Make path absolute if relative
        if [[ "$arg" != /* ]]; then
            arg="$SCRIPT_DIR/$arg"
        fi
        if [ ! -f "$arg" ]; then
            echo "ERROR: FBX file not found: $arg"
            exit 1
        fi
        SCENE_ARGS+=("$arg")
    done

    if [ ${#SCENE_ARGS[@]} -eq 0 ]; then
        echo "Running with Cornell box scene"
        SCENE_ARGS=("cornell-box")
    elif [ ${#SCENE_ARGS[@]} -eq 1 ] && echo "${SCENE_ARGS[0]}" | grep -iq "^cornell-box$"; then
        echo "Running with Cornell box scene"
    else
        echo "Running with ${#SCENE_ARGS[@]} FBX file(s):"
        for s in "${SCENE_ARGS[@]}"; do echo "  $s"; done
    fi

    echo "Console output -> log.txt"
    echo "---"

    "$EXE" "${SCENE_ARGS[@]}" 2>&1 | tee log.txt
fi
