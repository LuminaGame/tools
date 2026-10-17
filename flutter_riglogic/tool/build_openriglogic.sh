#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENRIGLOGIC_DIR="$DIR/third_party/openriglogic"
BUILD_DIR="$OPENRIGLOGIC_DIR/build"
OS="$(uname -s)"
JOBS="$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"

CMAKE_EXTRA_ARGS=()
if [ "$OS" = "Darwin" ]; then
  OSX_ARCH="$([ "$(uname -m)" = arm64 ] && echo arm64 || echo x86_64)"
  echo "Building OpenRigLogic static library for macOS ($OSX_ARCH) with -fPIC and system libc++..."
  CMAKE_EXTRA_ARGS+=(
    "-DCMAKE_OSX_ARCHITECTURES=$OSX_ARCH"
    -DCMAKE_CXX_FLAGS="-fPIC"
  )
else
  # flutter_filament's bundled libc++ (lumina repo, checked out beside this one).
  LIBCXX_DIR="${LUMINA_LIBCXX_DIR:-$DIR/../../lumina/flutter_filament/third_party/libcxx}"
  # The bundled libc++ has static libraries per architecture.
  case "$(uname -m)" in
    aarch64 | arm64) TRIPLET=aarch64-linux-gnu ;;
    *) TRIPLET=x86_64-linux-gnu ;;
  esac
  echo "Building OpenRigLogic static library with -fPIC, libc++, and global-dynamic TLS..."
  CMAKE_EXTRA_ARGS+=(
    -DCMAKE_CXX_FLAGS="-fPIC -nostdinc++ -Wno-unused-command-line-argument -ftls-model=global-dynamic -isystem $LIBCXX_DIR/usr/lib/llvm-21/include/c++/v1 -isystem $LIBCXX_DIR/usr/lib/llvm-21/include"
    -DCMAKE_SHARED_LINKER_FLAGS="-L$LIBCXX_DIR/usr/lib/$TRIPLET"
    -DCMAKE_EXE_LINKER_FLAGS="-L$LIBCXX_DIR/usr/lib/$TRIPLET"
  )
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

CC=clang CXX=clang++ cmake -B "$BUILD_DIR" -S "$OPENRIGLOGIC_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DRL_BUILD_PIC=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DRL_BUILD_TESTS=OFF \
    -DRL_BUILD_EXAMPLES=OFF \
    -DRL_BUILD_BENCHMARKS=OFF \
    "${CMAKE_EXTRA_ARGS[@]}"

cmake --build "$BUILD_DIR" -j"$JOBS"
mkdir -p "$OPENRIGLOGIC_DIR/lib"
cp "$BUILD_DIR"/libriglogic*.a "$OPENRIGLOGIC_DIR/lib/libriglogic.a"
echo "OpenRigLogic static library built at $OPENRIGLOGIC_DIR/lib/libriglogic.a"
