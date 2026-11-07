#!/bin/bash
# Smoke test of built WPE packages, before they are released: MirrorDash's own screen launcher, compiled
# against them as the OS image does, runs in labwc with a headless output and must draw and not crash.
# Run as root in a debian:trixie container: ./smoke-test.sh <dir with libwpewebkit-2.0-{1,dev}_*.deb>
# MIRRORDASH_REF: the MirrorDash branch or tag whose launcher to test (default master)
# What it can't catch: the Raspberry Pi's GPU (vc4). MirrorDash's OS test versions are the check for that.
set -euo pipefail
debs=$(realpath "${1:?the directory with the .debs}")
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends "$debs"/libwpewebkit-2.0-1_*.deb "$debs"/libwpewebkit-2.0-dev_*.deb \
    gcc libc6-dev pkg-config labwc ca-certificates curl > /dev/null

# The launcher and its start page, as MirrorDash's master (or MIRRORDASH_REF) has them now
raw=https://raw.githubusercontent.com/Menturan/MirrorDash/${MIRRORDASH_REF:-master}
curl -fsSL --retry 3 -o /tmp/mirrordash-screen.c "$raw/scripts/screen/mirrordash-screen.c"
mkdir -p /home/pi/mirrordash
curl -fsSL --retry 3 -o /home/pi/mirrordash/loading.html "$raw/mirrordash_core/static/loading.html"
# The same flags as MirrorDash's configure_image.sh step_screen
# shellcheck disable=SC2046  # pkg-config's flags are separate words
gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-error=deprecated-declarations -o /tmp/mirrordash-screen \
    /tmp/mirrordash-screen.c $(pkg-config --cflags --libs wpe-webkit-2.0 wpe-platform-2.0)

# labwc on wlroots' headless backend (one output, no GPU, no seat)
export XDG_RUNTIME_DIR=/tmp/xdg
mkdir -m 700 "$XDG_RUNTIME_DIR"
WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 labwc > /tmp/labwc.log 2>&1 &
for _ in $(seq 40); do [ -S "$XDG_RUNTIME_DIR/wayland-0" ] && break; sleep 0.5; done
[ -S "$XDG_RUNTIME_DIR/wayland-0" ] || { echo "labwc didn't start"; cat /tmp/labwc.log; exit 1; }

# No GPU here: Skia draws on the CPU. bubblewrap can't make its namespaces in a CI container, so WebKit's
# sandbox is off for this test only (it is on on a mirror)
export WAYLAND_DISPLAY=wayland-0 WPE_PLATFORM=wayland WEBKIT_SKIA_ENABLE_CPU_RENDERING=1 WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
code=0
WAYLAND_DEBUG=client timeout 30 /tmp/mirrordash-screen > /tmp/screen.log 2>&1 || code=$?
frames=$(grep -c 'wl_surface#[0-9]*\.attach' /tmp/screen.log || true)
echo "The launcher: exit $code (124: still running when the test ended), $frames frames drawn"
if [ "$code" -ne 124 ] || [ "$frames" -lt 5 ]; then
    echo "::error::The launcher didn't run on these packages"
    grep -vE '^\[[0-9. ]+\] ' /tmp/screen.log | tail -40
    tail -20 /tmp/labwc.log
    exit 1
fi
