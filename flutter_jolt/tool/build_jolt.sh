#!/usr/bin/env bash
# Unix counterpart of build_jolt.bat: fetches the pinned Jolt Physics release
# (tool/jolt_version.txt) into third_party/jolt/src and builds it as a static
# library with clang (against the bundled libc++ on Linux, system libc++ on
# macOS), -fPIC. Writes:
#   third_party/jolt/include/Jolt/...   the headers
#   third_party/jolt/lib/libJolt.a      the static library
#   third_party/jolt/jolt_defines.txt   the JPH_* defines Jolt was built with
#   third_party/jolt/VERSION            the tag and commit
# Usage: tool/build_jolt.sh [--clean]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOLT_DIR="$DIR/third_party/jolt"
SRC_DIR="$JOLT_DIR/src"
OS="$(uname -s)"
JOBS="$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
if [ "$OS" = "Darwin" ]; then
  BUILD_DIR="$JOLT_DIR/build-macos"
else
  BUILD_DIR="$JOLT_DIR/build-linux"
fi
LIBCXX_DIR="${LUMINA_LIBCXX_DIR:-$DIR/../../lumina/flutter_filament/third_party/libcxx}"
case "$(uname -m)" in
  aarch64 | arm64) TRIPLET=aarch64-linux-gnu; X86=OFF; OSX_ARCH=arm64 ;;
  *) TRIPLET=x86_64-linux-gnu; X86=ON; OSX_ARCH=x86_64 ;;
esac

JOLT_TAG="$(awk '$1 == "tag" { print $2 }' "$DIR/tool/jolt_version.txt")"
JOLT_COMMIT="$(awk '$1 == "commit" { print $2 }' "$DIR/tool/jolt_version.txt")"
[ -n "$JOLT_TAG" ] || { echo "tool/jolt_version.txt names no tag" >&2; exit 1; }

if [ "${1:-}" = "--clean" ]; then rm -rf "$JOLT_DIR"; fi
if [ ! -f "$SRC_DIR/Jolt/Jolt.h" ]; then
  echo "Fetching Jolt Physics $JOLT_TAG..."
  git clone --depth 1 --branch "$JOLT_TAG" https://github.com/jrouwe/JoltPhysics.git "$SRC_DIR"
fi
HEAD_COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD)"
if [ "$HEAD_COMMIT" != "$JOLT_COMMIT" ]; then
  echo "Jolt checkout is at $HEAD_COMMIT, expected $JOLT_COMMIT ($JOLT_TAG). Run with --clean." >&2
  exit 1
fi

CMAKE_EXTRA_ARGS=()
if [ "$OS" = "Darwin" ]; then
  echo "Building Jolt Physics $JOLT_TAG static library for macOS ($OSX_ARCH) with clang and system libc++..."
  CMAKE_EXTRA_ARGS+=(
    "-DCMAKE_OSX_ARCHITECTURES=$OSX_ARCH"
    -DCMAKE_CXX_FLAGS="-O2 -fPIC"
  )
else
  if [ ! -d "$LIBCXX_DIR/usr/lib/llvm-21/include/c++/v1" ]; then
    echo "The bundled libc++ is missing at $LIBCXX_DIR (set LUMINA_LIBCXX_DIR)." >&2
    exit 1
  fi
  echo "Building Jolt Physics $JOLT_TAG static library with clang and the bundled libc++..."
  CMAKE_EXTRA_ARGS+=(
    -DCMAKE_CXX_FLAGS="-O2 -fPIC -nostdinc++ -Wno-unused-command-line-argument -isystem $LIBCXX_DIR/usr/lib/llvm-21/include/c++/v1 -isystem $LIBCXX_DIR/usr/lib/llvm-21/include"
    -DCMAKE_EXE_LINKER_FLAGS="-L$LIBCXX_DIR/usr/lib/$TRIPLET"
  )
fi

CC=clang CXX=clang++ cmake -S "$SRC_DIR/Build" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DINTERPROCEDURAL_OPTIMIZATION=OFF \
  -DGENERATE_DEBUG_SYMBOLS=OFF \
  -DDOUBLE_PRECISION=OFF \
  -DCROSS_PLATFORM_DETERMINISTIC=OFF \
  -DOBJECT_LAYER_BITS=16 \
  -DCPP_EXCEPTIONS_ENABLED=ON \
  -DCPP_RTTI_ENABLED=ON \
  -DDEBUG_RENDERER_IN_DEBUG_AND_RELEASE=OFF \
  -DPROFILER_IN_DEBUG_AND_RELEASE=OFF \
  -DFLOATING_POINT_EXCEPTIONS_ENABLED=OFF \
  -DENABLE_ALL_WARNINGS=OFF \
  -DOVERRIDE_CXX_FLAGS=OFF \
  -DUSE_SSE4_1=$X86 -DUSE_SSE4_2=$X86 \
  -DUSE_AVX=OFF -DUSE_AVX2=OFF -DUSE_AVX512=OFF \
  -DUSE_LZCNT=OFF -DUSE_TZCNT=OFF -DUSE_F16C=OFF -DUSE_FMADD=OFF \
  -DJPH_USE_DX12=OFF -DJPH_USE_VK=OFF -DJPH_USE_MTL=OFF -DJPH_USE_CPU_COMPUTE=OFF \
  -DENABLE_OBJECT_STREAM=OFF -DENABLE_INSTALL=OFF \
  -DTARGET_UNIT_TESTS=OFF -DTARGET_HELLO_WORLD=OFF -DTARGET_PERFORMANCE_TEST=OFF \
  -DTARGET_SAMPLES=OFF -DTARGET_VIEWER=OFF \
  "${CMAKE_EXTRA_ARGS[@]}"
cmake --build "$BUILD_DIR" --target Jolt -j"$JOBS"

mkdir -p "$JOLT_DIR/lib"
cp "$BUILD_DIR/libJolt.a" "$JOLT_DIR/lib/libJolt.a"
rm -rf "$JOLT_DIR/include"
mkdir -p "$JOLT_DIR/include"
(cd "$SRC_DIR" && find Jolt \( -name '*.h' -o -name '*.inl' \) | tar -cf - -T - | tar -xf - -C "$JOLT_DIR/include")
dart "$DIR/tool/write_jolt_defines.dart" "$BUILD_DIR/compile_commands.json" "$JOLT_DIR/jolt_defines.txt"
printf 'tag %s\ncommit %s\n' "$JOLT_TAG" "$JOLT_COMMIT" > "$JOLT_DIR/VERSION"
echo "Jolt Physics $JOLT_TAG built at $JOLT_DIR"
