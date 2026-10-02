#!/usr/bin/env bash
# Builds the kimodo.cpp prebuilt flutter_kimodo bundles (Linux x64); the
# counterpart of tool/build_kimodo.ps1.
#
#   tool/build_kimodo.sh [--vulkan auto|on|off] [--work <dir>] [--clean]
#
# Checks out the pinned kimodo.cpp commit (tool/kimodo/UPSTREAM) with its ggml
# submodule, builds it through tool/kimodo/CMakeLists.txt (which compiles
# native/kimodo_lumina.cpp into libkimodo.so; every library gets
# RUNPATH=$ORIGIN), stages the shared libraries, headers, licences and
# lumina-kimodo.json, packs <work>/dist/kimodo-<VERSION>-linux-x64.tar.gz +
# .sha256 and installs the folder at <work>/prebuilt/<VERSION>/linux-x64.
#
# Needs: CMake >= 3.25, Ninja, a C++23 compiler (GCC 13+ or clang 17+ with
# libstdc++ 13+), git; for Vulkan the Vulkan SDK / glslc and the Vulkan
# headers (libvulkan-dev).
set -euo pipefail

vulkan=auto
work=""
clean=0
while [ $# -gt 0 ]; do
  case "$1" in
    --vulkan) vulkan="$2"; shift 2 ;;
    --work) work="$2"; shift 2 ;;
    --clean) clean=1; shift ;;
    *) echo "usage: $0 [--vulkan auto|on|off] [--work <dir>] [--clean]" >&2; exit 2 ;;
  esac
done

here="$(cd "$(dirname "$0")" && pwd)"
package="$(dirname "$here")"
work="${work:-${LUMINA_KIMODO_WORK:-$package/third_party/kimodo}}"
version="$(tr -d '[:space:]' < "$here/kimodo/VERSION")"
repository="$(sed -n 's/^repository=//p' "$here/kimodo/UPSTREAM")"
commit="$(sed -n 's/^commit=//p' "$here/kimodo/UPSTREAM")"
name="kimodo-$version-linux-x64"
src="$work/src"; out="$work/out"; dist="$work/dist"; install="$work/prebuilt/$version/linux-x64"
log() { echo "[build_kimodo] $*"; }
log "kimodo.cpp $commit -> $name"

for tool in cmake ninja git; do
  command -v "$tool" >/dev/null || { echo "$tool is not installed" >&2; exit 1; }
done

glslc="$(command -v glslc || true)"
[ -z "$glslc" ] && [ -n "${VULKAN_SDK:-}" ] && [ -x "$VULKAN_SDK/bin/glslc" ] && glslc="$VULKAN_SDK/bin/glslc"
case "$vulkan" in
  on) [ -n "$glslc" ] || { echo "Vulkan requested but glslc (Vulkan SDK) is missing" >&2; exit 1; }; vk=ON ;;
  off) vk=OFF ;;
  *) if [ -n "$glslc" ]; then vk=ON; else vk=OFF; fi ;;
esac
log "Vulkan backend: $vk"

[ "$clean" = 1 ] && rm -rf "$out"
if [ ! -d "$src/.git" ]; then
  mkdir -p "$src"
  git -C "$src" init -q
  git -C "$src" remote add origin "$repository"
fi
if [ "$(git -C "$src" rev-parse --verify -q HEAD || true)" != "$commit" ]; then
  log "fetching $commit"
  git -C "$src" fetch -q --depth 1 origin "$commit"
  git -C "$src" checkout -q --force "$commit"
fi
git -C "$src" submodule update --init --depth 1 -q
ggml="$(git -C "$src/ggml" rev-parse HEAD)"
log "ggml $ggml"

cfg=(-DKIMODO_SOURCE_DIR="$src" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF
  -DKIMODO_BUILD_TESTS=OFF -DKIMODO_ENABLE_VULKAN="$vk")
[ "$vk" = ON ] && cfg+=(-DVulkan_GLSLC_EXECUTABLE="$glslc")
cmake -S "$here/kimodo" -B "$out" -G Ninja "${cfg[@]}"
cmake --build "$out" --target kimodo kmd-generate kmd-inspect

stage="$dist/stage/$name"
rm -rf "$dist/stage"
mkdir -p "$stage/lib" "$stage/bin" "$stage/include/kimodo" "$stage/licenses"
find "$out" -name 'libkimodo.so*' -o -name 'libggml*.so*' | while read -r f; do cp -P "$f" "$stage/lib/"; done
[ -e "$stage/lib/libkimodo.so" ] || { echo "libkimodo.so was not built" >&2; exit 1; }
for exe in kmd-generate kmd-inspect; do
  f="$(find "$out" -name "$exe" -type f | head -n1)"; [ -n "$f" ] && cp "$f" "$stage/bin/"
done
cp "$src"/include/kimodo/* "$stage/include/kimodo/"
cp "$package/native/kimodo_lumina.h" "$stage/include/"
cp "$src/LICENSE" "$stage/licenses/kimodo.cpp-LICENSE.txt"
cp "$src/NOTICE" "$stage/licenses/kimodo.cpp-NOTICE.txt"
cp "$src/ggml/LICENSE" "$stage/licenses/ggml-LICENSE.txt"
backends='"cpu"'; [ "$vk" = ON ] && backends='"cpu", "vulkan"'
compiler="$(sed -n 's/^CMAKE_CXX_COMPILER:[A-Z]*=//p' "$out/CMakeCache.txt")"
cat > "$stage/lumina-kimodo.json" <<EOF
{
  "version": "$version",
  "platform": "linux-x64",
  "upstream": { "repository": "$repository", "commit": "$commit", "ggml": "$ggml" },
  "backends": [$backends],
  "build": { "compiler": "$compiler" }
}
EOF

archive="$dist/$name.tar.gz"
tar -C "$dist/stage" -czf "$archive" "$name"
(cd "$dist" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
rm -rf "$install"; mkdir -p "$(dirname "$install")"
mv "$stage" "$install"; rm -rf "$dist/stage"
log "$archive sha256 $(cut -d' ' -f1 < "$archive.sha256")"
log "installed at $install"
