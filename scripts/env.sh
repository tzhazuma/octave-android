#!/usr/bin/env bash
# Shared environment for the Octave -> Android NDK cross build (route B).
# Source this from the other build scripts:  . "$(dirname "$0")/env.sh"
#
# IMPORTANT PATH TRAP (cost us one failed build):
#   `which clang` on this machine resolves to ~/toolchains/ATfE-*/bin/clang,
#   the *Arm Toolchain for Embedded* bare-metal compiler. It has no host
#   sysroot, so any host-side tool build fails with `stdio.h file not found`.
#   HOSTCC is therefore pinned to the Apple/Xcode clang below.

export OCTAVE_ANDROID_ROOT="${OCTAVE_ANDROID_ROOT:-$HOME/octave-android}"

# --- Android NDK -------------------------------------------------------------
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
NDK_HOST_TAG="darwin-x86_64"          # universal binary; correct on arm64 macOS too
export NDK_BIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$NDK_HOST_TAG/bin"

export ANDROID_API="${ANDROID_API:-24}"
export TARGET_TRIPLE="aarch64-linux-android"
export CC_TARGET="$NDK_BIN/aarch64-linux-android${ANDROID_API}-clang"
export CXX_TARGET="$NDK_BIN/aarch64-linux-android${ANDROID_API}-clang++"
export AR_TARGET="$NDK_BIN/llvm-ar"
export RANLIB_TARGET="$NDK_BIN/llvm-ranlib"
export STRIP_TARGET="$NDK_BIN/llvm-strip"
export READELF="$NDK_BIN/llvm-readelf"
export NM="$NDK_BIN/llvm-nm"

# --- host toolchain (for build-time helpers such as OpenBLAS getarch) --------
export HOSTCC="/usr/bin/clang"        # Apple clang; NOT the ATfE one
export HOSTCXX="/usr/bin/clang++"

# --- Android 16 / 16 KiB page size ------------------------------------------
export ANDROID_LDFLAGS="-Wl,-z,max-page-size=16384"

# --- install prefix ----------------------------------------------------------
export PREFIX_ARM64="$OCTAVE_ANDROID_ROOT/prefix/arm64-v8a"

# --- flang (Fortran) ---------------------------------------------------------
# Host flang comes from `brew install flang`; it cross-compiles with
#   flang-new --target=aarch64-linux-android<API>
# The aarch64 Fortran *runtime* is a prebuilt from Termux's
# ndk-toolchain-clang-with-flang (r30) release -- see scripts/fetch_flang_runtime.sh
export FLANG_BIN="${FLANG_BIN:-/opt/homebrew/opt/flang/bin/flang-new}"
export FLANG_RT_DIR="${FLANG_RT_DIR:-$OCTAVE_ANDROID_ROOT/downloads/flang-r30/build-aarch64-install}"
export FLANG_RT_LIB="$FLANG_RT_DIR/libflang_rt.runtime.a"

octave_android_echo_env() {
  echo "OCTAVE_ANDROID_ROOT = $OCTAVE_ANDROID_ROOT"
  echo "ANDROID_NDK_ROOT    = $ANDROID_NDK_ROOT"
  echo "CC_TARGET           = $CC_TARGET"
  echo "HOSTCC              = $HOSTCC"
  echo "PREFIX_ARM64        = $PREFIX_ARM64"
  echo "FLANG_BIN           = $FLANG_BIN"
  echo "FLANG_RT_LIB        = $FLANG_RT_LIB"
}
