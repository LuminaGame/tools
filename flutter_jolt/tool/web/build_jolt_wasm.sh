#!/usr/bin/env bash
# Builds flutter_jolt for the web: the pinned Jolt Physics release
# (tool/jolt_version.txt) and the C wrapper (src/jolt_c.cpp) as one
# WebAssembly module, web/flutter_jolt.{js,wasm} (gitignored). The module is
# single-threaded (no SharedArrayBuffer, so no COOP/COEP headers), uses WASM
# SIMD, and exports every jolt_* function of src/jolt_c.h, so the web Dart
# layer (lib/src/web_ffi/, lib/src/jolt_bindings.web.g.dart) calls the same
# C API as the desktop library.
#
# Toolchain: emsdk (default ~/emsdk, else EMSDK=...) and a Dart SDK on PATH
# (for tool/write_jolt_defines.dart). Writes, besides the module:
#   third_party/jolt-wasm/src         the Jolt checkout
#   third_party/jolt-wasm/build       the Jolt static library for wasm32
#   third_party/jolt-wasm/jolt_defines.txt  the JPH_* defines Jolt was built with
# Usage: tool/web/build_jolt_wasm.sh [--clean]      OPT=-O1 for faster links
set -euo pipefail
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WASM_DIR="$PKG/third_party/jolt-wasm"
SRC_DIR="$WASM_DIR/src"
BUILD_DIR="$WASM_DIR/build"
OUT_DIR="$PKG/web"
OPT="${OPT:--O3}"
EMSDK="${EMSDK:-$HOME/emsdk}"

JOLT_TAG="$(awk '$1 == "tag" { print $2 }' "$PKG/tool/jolt_version.txt")"
JOLT_COMMIT="$(awk '$1 == "commit" { print $2 }' "$PKG/tool/jolt_version.txt")"
[ -n "$JOLT_TAG" ] || { echo "tool/jolt_version.txt names no tag" >&2; exit 1; }

if [ ! -f "$EMSDK/emsdk_env.sh" ]; then
  echo "No emsdk at $EMSDK (set EMSDK)." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$EMSDK/emsdk_env.sh" >/dev/null 2>&1
command -v dart >/dev/null || { echo "A Dart SDK must be on PATH (tool/write_jolt_defines.dart)." >&2; exit 1; }

if [ "${1:-}" = "--clean" ]; then rm -rf "$WASM_DIR"; fi
if [ ! -f "$SRC_DIR/Jolt/Jolt.h" ]; then
  echo "Fetching Jolt Physics $JOLT_TAG..."
  git clone --depth 1 --branch "$JOLT_TAG" https://github.com/jrouwe/JoltPhysics.git "$SRC_DIR"
fi
HEAD_COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD)"
if [ "$HEAD_COMMIT" != "$JOLT_COMMIT" ]; then
  echo "Jolt checkout is at $HEAD_COMMIT, expected $JOLT_COMMIT ($JOLT_TAG). Run with --clean." >&2
  exit 1
fi

echo "Building Jolt Physics $JOLT_TAG for WebAssembly..."
emcmake cmake -S "$SRC_DIR/Build" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DINTERPROCEDURAL_OPTIMIZATION=OFF \
  -DGENERATE_DEBUG_SYMBOLS=OFF \
  -DDOUBLE_PRECISION=OFF \
  -DCROSS_PLATFORM_DETERMINISTIC=OFF \
  -DOBJECT_LAYER_BITS=16 \
  -DCPP_EXCEPTIONS_ENABLED=OFF \
  -DCPP_RTTI_ENABLED=ON \
  -DDEBUG_RENDERER_IN_DEBUG_AND_RELEASE=OFF \
  -DPROFILER_IN_DEBUG_AND_RELEASE=OFF \
  -DFLOATING_POINT_EXCEPTIONS_ENABLED=OFF \
  -DENABLE_ALL_WARNINGS=OFF \
  -DUSE_WASM_SIMD=ON \
  -DJPH_USE_DX12=OFF -DJPH_USE_VK=OFF -DJPH_USE_MTL=OFF -DJPH_USE_CPU_COMPUTE=OFF \
  -DENABLE_OBJECT_STREAM=OFF -DENABLE_INSTALL=OFF \
  -DTARGET_UNIT_TESTS=OFF -DTARGET_HELLO_WORLD=OFF -DTARGET_PERFORMANCE_TEST=OFF \
  -DTARGET_SAMPLES=OFF -DTARGET_VIEWER=OFF
cmake --build "$BUILD_DIR" --target Jolt -j"$(nproc)"
dart "$PKG/tool/write_jolt_defines.dart" "$BUILD_DIR/compile_commands.json" "$WASM_DIR/jolt_defines.txt"

# Every jolt_* function the header exports, plus the allocator the web layer uses.
EXPORTS="$(grep -oE 'JOLT_C_EXPORT[^(]*[^a-z_0-9](jolt_[a-z0-9_]+)\(' "$PKG/src/jolt_c.h" \
  | sed -E 's/.*(jolt_[a-z0-9_]+)\($/"_\1"/' | sort -u | paste -sd, -)"
DEFINES="$(sed -e '/^#/d' -e '/^$/d' -e 's/^/-D/' "$WASM_DIR/jolt_defines.txt" | paste -sd' ' -)"

mkdir -p "$OUT_DIR"
echo "Linking web/flutter_jolt.{js,wasm} ($OPT)..."
# Jolt's own flags for wasm32 (USE_WASM_SIMD): WASM SIMD with Emscripten's
# SSE 4.2 emulation, which Jolt's headers select from the compiler.
# shellcheck disable=SC2086
em++ $OPT -std=c++20 -msimd128 -msse4.2 -ffp-contract=off -DNDEBUG $DEFINES -fno-exceptions \
  -I"$SRC_DIR" "$PKG/src/jolt_c.cpp" "$BUILD_DIR/libJolt.a" \
  -o "$OUT_DIR/flutter_jolt.js" \
  -sMODULARIZE=1 -sEXPORT_NAME=FlutterJolt \
  -sENVIRONMENT=web,node \
  -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=67108864 -sSTACK_SIZE=16777216 \
  -sWASM_BIGINT=1 -sALLOW_TABLE_GROWTH=1 \
  -sEXPORTED_FUNCTIONS="[$EXPORTS,\"_malloc\",\"_free\"]" \
  -sEXPORTED_RUNTIME_METHODS='["HEAPU8","addFunction","removeFunction"]'
printf 'tag %s\ncommit %s\n' "$JOLT_TAG" "$JOLT_COMMIT" > "$WASM_DIR/VERSION"
ls -l "$OUT_DIR/flutter_jolt.js" "$OUT_DIR/flutter_jolt.wasm"
echo "flutter_jolt web module built at $OUT_DIR ($(grep -o '"_jolt_' <<< "$EXPORTS" | wc -l) exports)"
