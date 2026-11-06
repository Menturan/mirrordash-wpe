# WPE WebKit for the MirrorDash OS

[MirrorDash](https://github.com/Menturan/MirrorDash)'s screen runs on [WPE WebKit](https://wpewebkit.org).
Debian trixie, which the MirrorDash OS is built on, ships WPE 2.48.3 and gives it no security fixes
("wpewebkit is generally unsupported from bookworm onwards", Debian's `security-support.deb13`).
So this repository rebuilds Debian sid's `wpewebkit` package for trixie arm64, and publishes each
version as a release. The MirrorDash OS image installs the newest one.

- **Check Debian** (`check.yml`) runs every Monday: when sid has a version without a release, it
  starts **Build**.
- **Build** (`build.yml`) fetches Debian's source with `dget`, which checks its signature against
  Debian's keyring, builds it in a trixie container on GitHub's arm64 runner and publishes the
  packages with a `SHA256SUMS`. The changes to Debian's build: the version gets `~mirrordashN` (N is
  `MIRRORDASH_BUILD` in `build.yml`, one up whenever the build changes), there is no debug info and
  no precompiled headers (so the compiler cache works across runs), and what the mirror's screen
  never uses is turned off: speech synthesis (flite, 27 MB), spell checking, XSLT, PDF.js, gamepads,
  camera and recording, MHTML, accessibility (ATK), the legacy libwpe API, the DRM and headless
  platforms, MiniBrowser and tracing. Less to build, to ship in the image and to attack.
  A cold build takes about 2.5 hours; one that runs out of time keeps its compiler cache, so running
  it again continues.

To build a version by hand: `gh workflow run build.yml -f version=2.54.2-1`.

The scripts here are under the AGPL-3.0 like MirrorDash; WPE WebKit itself is LGPL/BSD, and its
source is Debian's, linked from each release.
