#!/usr/bin/env bash
# Fetch the prebuilt aarch64-linux-android Fortran runtime (libflang_rt.runtime.a).
#
# This is THE artifact that unblocks route B: it is the Fortran runtime that a
# flang-compiled object must be linked against on Android. Termux publishes it
# prebuilt, so we do NOT need to build LLVM/flang from source (which would need
# ~40+ GiB and hours; this box has ~15 GiB free).
#
# Source: https://github.com/termux/ndk-toolchain-clang-with-flang/releases/tag/r30
# The sha256 below is the one Termux's own scripts/build/setup/termux_setup_flang.sh
# pins, so we verify against upstream, not against ourselves.
set -euo pipefail

ROOT="${OCTAVE_ANDROID_ROOT:-$HOME/octave-android}"
DEST="$ROOT/downloads/flang-r30"
ASSET="package-flang-aarch64.tar.bz2"
SHA256="47a57240cfe454d20d2b7181ed216e7c529e15c8e3002d890d02f8e64ab999c7"
URL="https://github.com/termux/ndk-toolchain-clang-with-flang/releases/download/r30/$ASSET"

mkdir -p "$DEST"
cd "$DEST"

if [ ! -f "$ASSET" ]; then
  echo "==> downloading $ASSET"
  curl -L --retry 3 --retry-all-errors -o "$ASSET" "$URL"
fi

echo "==> verifying sha256 against Termux's pinned value"
echo "$SHA256  $ASSET" | shasum -a 256 -c -

echo "==> extracting"
tar xjf "$ASSET"

RT="$DEST/build-aarch64-install/libflang_rt.runtime.a"
ls -l "$RT"
echo "==> archive members: $(NDK_BIN=${NDK_BIN:-$HOME/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin}; "$NDK_BIN/llvm-ar" t "$RT" | wc -l)"
echo "==> done: $RT"
