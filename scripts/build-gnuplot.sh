#!/usr/bin/env bash
# Build the gnuplot that Octave's graphics toolkit shells out to.
#
# Octave here has no Qt and no FLTK -- both need a toolchain far larger than the
# interpreter -- so the only way from plot(...) to pixels is the gnuplot toolkit. It
# writes SVG, which the app hands to a WebView: no cairo, no libgd, no fontconfig.
#
# The one source change is in patches/gnuplot-android.patch: gnuplot calls
# setuid(getuid()) as a "did I accidentally get installed suid?" guard, and Android's
# seccomp policy makes setuid() a fatal SIGSYS for app processes, so the child dies
# with "Bad system call" before drawing anything.
set -euo pipefail

ROOT="$HOME/octave-android"
SRC="$ROOT/src/gnuplot-6.0.0"
NDK="$HOME/Library/Android/sdk/ndk/28.2.13676358"
TC="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

if [ ! -d "$SRC" ]; then
  cd "$ROOT/src"
  tar xzf "$ROOT/downloads/gnuplot-6.0.0.tar.gz"
fi
cd "$SRC"

if ! grep -q 'defined(__ANDROID__)' src/plot.c; then
  patch -p1 < "$ROOT/patches/gnuplot-android.patch"
fi

export CC="$TC/bin/aarch64-linux-android24-clang" \
       CXX="$TC/bin/aarch64-linux-android24-clang++" \
       AR="$TC/bin/llvm-ar" RANLIB="$TC/bin/llvm-ranlib"

# --without-qt is not enough on its own: with Qt present in /usr/local, configure picks
# it up and the build fails on a host-only Qt header. Both flags are needed.
./configure --host=aarch64-linux-android --build=aarch64-apple-darwin \
  --without-x --disable-wxwidgets --without-qt --without-lua \
  --without-cairo --without-gd --without-pango --disable-plugins \
  --disable-readline --without-readline

make -j8 gnuplot
ls -la src/gnuplot
