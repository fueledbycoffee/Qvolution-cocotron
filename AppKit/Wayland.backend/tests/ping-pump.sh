#!/usr/bin/env bash
set -euo pipefail
src=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?supply private build directory}
mkdir -p "$out"
wayland-scanner server-header /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml "$out/xdg-shell-server.h"
wayland-scanner private-code /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml "$out/xdg-shell-protocol.c"
cat > "$out/build.ninja" <<NINJA
rule cc
  command = cc -std=gnu11 -g -O1 -Wall -Wextra -Wno-unused-parameter -Wno-unused-function -fsanitize=address,undefined -fno-omit-frame-pointer -pthread -I$src -I$out $(pkg-config --cflags wayland-client wayland-server xkbcommon) \$in -o \$out $(pkg-config --libs wayland-client wayland-server)
build $out/ping-pump: cc $src/tests/ping-wire-peer.c $out/xdg-shell-protocol.c | $src/WaylandEventPump.h $src/WaylandLibrary.h
NINJA
ninja -C "$out" -j6
ninja -C "$out" -n
ASAN_OPTIONS=detect_leaks=1 "$out/ping-pump"
# Negative control: the same main-thread stall must leave pings unanswered.
set +e
ASAN_OPTIONS=detect_leaks=0 "$out/ping-pump" --main-thread-reader > "$out/negative-control.log" 2>&1
result=$?
set -e
[[ $result != 0 ]] && grep -q 'received == 20' "$out/negative-control.log"
printf 'negative_control_failed_as_expected=true exit=%s\n' "$result"
