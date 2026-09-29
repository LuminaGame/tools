#!/bin/bash
# Builds capture_probe (the mouse-capture core in a plain GTK window) into $1
# (default: a temp dir). Needs g++, gtk+-3.0, wayland-client, wayland-scanner
# and wayland-protocols.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="$HERE/../../linux"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT/gen"
PROTO="$(pkg-config --variable=pkgdatadir wayland-protocols)"
for p in pointer-constraints relative-pointer; do
  xml="$PROTO/unstable/$p/$p-unstable-v1.xml"
  wayland-scanner client-header "$xml" "$OUT/gen/$p-unstable-v1-client-protocol.h"
  wayland-scanner private-code "$xml" "$OUT/gen/$p-unstable-v1-protocol.c"
  gcc -c -fPIC -O1 $(pkg-config --cflags wayland-client) "$OUT/gen/$p-unstable-v1-protocol.c" -o "$OUT/$p.o"
done
g++ -std=c++17 -O1 -Wall -Werror -DLUMINA_MC_WAYLAND_PROTOCOLS=1 -I"$OUT/gen" \
  $(pkg-config --cflags gtk+-3.0 wayland-client) \
  "$HERE/capture_probe.cc" "$LINUX/mouse_capture_core.cc" "$OUT"/*.o \
  $(pkg-config --libs gtk+-3.0 wayland-client) -o "$OUT/capture_probe"
echo "$OUT/capture_probe"
