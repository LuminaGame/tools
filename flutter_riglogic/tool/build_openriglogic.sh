#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENRIGLOGIC_DIR="$DIR/third_party/openriglogic"
BUILD_DIR="$OPENRIGLOGIC_DIR/build"
# flutter_filament's bundled libc++ (lumina repo, checked out beside this one).
LIBCXX_DIR="${LUMINA_LIBCXX_DIR:-$DIR/../../lumina/flutter_filament/third_party/libcxx}"

echo "Building OpenRigLogic static library with -fPIC, libc++, and global-dynamic TLS..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

CC=clang CXX=clang++ cmake -B "$BUILD_DIR" -S "$OPENRIGLOGIC_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DRL_BUILD_PIC=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DRL_BUILD_TESTS=OFF \
    -DRL_BUILD_EXAMPLES=OFF \
    -DRL_BUILD_BENCHMARKS=OFF \
    -DCMAKE_CXX_FLAGS="-fPIC -nostdinc++ -Wno-unused-command-line-argument -ftls-model=global-dynamic -isystem $LIBCXX_DIR/usr/lib/llvm-21/include/c++/v1 -isystem $LIBCXX_DIR/usr/lib/llvm-21/include" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L$LIBCXX_DIR/usr/lib/x86_64-linux-gnu" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$LIBCXX_DIR/usr/lib/x86_64-linux-gnu"

cmake --build "$BUILD_DIR" -j"$(nproc)"
mkdir -p "$OPENRIGLOGIC_DIR/lib"
cp "$BUILD_DIR"/libriglogic*.a "$OPENRIGLOGIC_DIR/lib/libriglogic.a"
echo "OpenRigLogic static library built at $OPENRIGLOGIC_DIR/lib/libriglogic.a"
