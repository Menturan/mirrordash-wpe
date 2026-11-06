#!/bin/bash
# Builds Debian's wpewebkit source in src/ (unpacked by dget) for trixie, without what the MirrorDash screen
# never uses, and writes NOTES.md (what changed since the last release) and DEPENDS.txt next to src/.
# Run by build.yml as root in a debian:trixie container, from the repository's root:
#   VERSION=<Debian version> MIRRORDASH_BUILD=<n> GITHUB_REPOSITORY=<owner/repo> ./build.sh
set -euo pipefail
: "${VERSION:?}" "${MIRRORDASH_BUILD:?}" "${GITHUB_REPOSITORY:?}"
root=$PWD
cd src/wpewebkit-*/
apt-get build-dep -y .

# The release notes: Debian's own entries since the version of the last release (its security fixes list
# WebKit's WSA numbers), before our entry is added
last=$(curl -fsSI --retry 3 "https://github.com/$GITHUB_REPOSITORY/releases/latest" | awk -F/ 'tolower($1) ~ /^location:/ {print $NF}' | tr -d '\r') || true
last_version=$(sed -nE 's/^v(.+)-mirrordash[0-9]+$/\1/p' <<< "$last")
{
  echo "## Debian's changes since the last release (${last:-none})"
  if [ -z "$last_version" ]; then echo "(no earlier release)"
  elif [ "$last_version" = "$VERSION" ]; then echo "The same Debian version: only this build changed."
  else echo '```'; dpkg-parsechangelog --since "$last_version" -S Changes; echo '```'; fi
} > "$root/NOTES.md"

dch -b -v "${VERSION}~mirrordash${MIRRORDASH_BUILD}" --distribution trixie --force-distribution \
  "Rebuilt for trixie, whose own WPE gets no security fixes, without what the MirrorDash screen never uses."
# No precompiled headers: each runner builds them with different bytes, so ccache could reuse no object
# compiled against one (learnt from dariyooo/wpe-webkit-binaries)
sed -i 's/^EXTRA_CMAKE_ARGUMENTS = -DPORT=WPE /&-DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON /' debian/rules
grep -q DISABLE_PRECOMPILE_HEADERS debian/rules  # Debian's rules changed: look at the line again
# Off: what the mirror's screen never uses (speech, spell checking, XSLT, PDF.js, accessibility, libwpe,
# the DRM and headless platforms): less to ship and attack. Only WebKit's public build options, the ones
# it supports packagers changing; after Debian's own flags, so these win.
trim="-DENABLE_SPEECH_SYNTHESIS=OFF -DUSE_FLITE=OFF -DENABLE_SPELLCHECK=OFF -DENABLE_XSLT=OFF"
trim+=" -DENABLE_PDFJS=OFF -DUSE_ATK=OFF -DENABLE_WPE_LEGACY_API=OFF"
trim+=" -DENABLE_WPE_PLATFORM_DRM=OFF -DENABLE_WPE_PLATFORM_HEADLESS=OFF"
sed -i "s|^\tdh_auto_configure -- \$(EXTRA_CMAKE_ARGUMENTS)\$|& $trim|" debian/rules
grep -q "ENABLE_SPEECH_SYNTHESIS=OFF" debian/rules  # Debian's rules changed: look at the line again

# WebCore's unified sources take 2-3 GB each to compile: one job per 4 GB, or the compiler is killed
mem=$(free -g | awk '/^Mem:/{print $2}')
jobs=$(( mem / 4 )); jobs=$(( jobs < 1 ? 1 : jobs > $(nproc) ? $(nproc) : jobs ))
echo "$(nproc) CPUs, $mem GB: $jobs jobs"
start=$(date +%s)
# No debug info (the -g Debian's rules turn into -g1): smaller objects, a quicker link
DEB_CFLAGS_STRIP="-g" DEB_CXXFLAGS_STRIP="-g" \
  DEB_BUILD_OPTIONS="nocheck nodoc noautodbgsym parallel=$jobs" dpkg-buildpackage -B -us -uc 2>&1 | tee ../build.log
# CMake only warns about an option it doesn't know: one WebKit renamed would quietly be back on
unknown=$(grep -A30 "Manually-specified variables were not used" ../build.log \
  | grep -oE "^ +[A-Z_0-9]+" | tr -d " " | grep -xF -f <(grep -oE -- "-D[A-Z_0-9]+=" <<< "$trim" | sed "s/^-D//; s/=$//")) || true
[ -z "$unknown" ] || { echo "::error::WebKit no longer knows: $unknown; find what they are called now"; exit 1; }
echo "Build took $(( ($(date +%s) - start) / 60 )) minutes"

# What the packages need, against the last release
cd "$root"
dpkg-deb -f src/libwpewebkit-2.0-1_*.deb Depends | tr ',' '\n' | sed 's/^ *//' | sort > DEPENDS.txt
{
  echo; echo "## Runtime dependencies against the last release"
  if curl -fsSL --retry 3 -o /tmp/last-depends "https://github.com/$GITHUB_REPOSITORY/releases/latest/download/DEPENDS.txt"; then
    echo '```diff'; { diff -u /tmp/last-depends DEPENDS.txt || true; } | tail -n +3; echo '```'
  else echo "(the last release has no DEPENDS.txt)"; fi
} >> NOTES.md
