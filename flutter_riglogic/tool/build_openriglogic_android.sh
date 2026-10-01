#!/usr/bin/env bash
# Builds OpenRigLogic as a static library for Android (arm64-v8a, x86_64) using the Android NDK and CMake.
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENRIGLOGIC_DIR="$DIR/third_party/openriglogic"

# 1. Locate Android NDK
NDK_DIR="${ANDROID_NDK_HOME:-${ANDROID_NDK:-${ANDROID_HOME}/ndk}}"
if [ -z "$NDK_DIR" ] || [ ! -d "$NDK_DIR" ]; then
    # Pick latest NDK if directory exists
    if [ -d "$HOME/Android/Sdk/ndk" ]; then
        NDK_DIR="$(find "$HOME/Android/Sdk/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
    fi
fi

if [ -z "$NDK_DIR" ] || [ ! -d "$NDK_DIR" ]; then
    echo "Error: Android NDK not found. Set ANDROID_NDK_HOME." >&2
    exit 1
fi
echo "Using Android NDK: $NDK_DIR"

TARGET_ABIS="${1:-arm64-v8a x86_64 armeabi-v7a}"

for ABI in $TARGET_ABIS; do
    echo "========================================================"
    echo "Building OpenRigLogic for Android ABI: $ABI"
    echo "========================================================"
    BUILD_DIR="$OPENRIGLOGIC_DIR/build-android-$ABI"
    OUT_DIR="$OPENRIGLOGIC_DIR/lib/android/$ABI"

    mkdir -p "$OUT_DIR"

    cmake -S "$OPENRIGLOGIC_DIR" -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$NDK_DIR/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM=android-26 \
        -DCMAKE_BUILD_TYPE=Release \
        -DANDROID_STL=c++_shared \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_CXX_FLAGS="-fPIC" \
        -DCMAKE_C_FLAGS="-fPIC" \
        -DBUILD_SHARED_LIBS=OFF \
        -DRL_BUILD_TESTS=OFF \
        -DRL_BUILD_EXAMPLES=OFF \
        -DRL_BUILD_BENCHMARKS=OFF

    cmake --build "$BUILD_DIR" -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

    cp "$BUILD_DIR"/libriglogic*.a "$OUT_DIR/libriglogic.a"
    echo "Copied to $OUT_DIR/libriglogic.a"
done

echo "Android OpenRigLogic libraries successfully built!"
