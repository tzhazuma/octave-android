#!/usr/bin/env bash
# Termux-style NDK + LLVM-Flang cross toolchain for aarch64-linux-android.
# Mirrors termux_setup_flang: host flang-new + --target=aarch64-linux-android<API>
# + target flang runtime unpacked into the sysroot lib dir.
# Verified working: Homebrew flang 23.1.3 + NDK r28 (clang 19) + Termux flang r30 runtime.
set -euo pipefail
export OCTAVE_ANDROID_ROOT="${OCTAVE_ANDROID_ROOT:-$HOME/octave-android}"
export ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-24}"
export NDK="${NDK:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
export TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
export SYSROOT="$TOOLCHAIN/sysroot"
export TARGET_TRIPLE="aarch64-linux-android"
export TARGET="${TARGET_TRIPLE}${ANDROID_API_LEVEL}"
export PREFIX="$OCTAVE_ANDROID_ROOT/prefix/arm64-v8a"
export FLANG_RT_DIR="$PREFIX/flang-runtime"
export HOST_FLANG="${HOST_FLANG:-/opt/homebrew/bin/flang-new}"

# C/C++ (NDK)
export CC="$TOOLCHAIN/bin/${TARGET}-clang"
export CXX="$TOOLCHAIN/bin/${TARGET}-clang++"
export CPP="$CC -E"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export NM="$TOOLCHAIN/bin/llvm-nm"
export LD="$TOOLCHAIN/bin/ld.lld"
# Fortran (LLVM Flang, cross)
export FC="$HOST_FLANG"
export F77="$HOST_FLANG"
export FCFLAGS="--target=${TARGET} -D__ANDROID_API__=${ANDROID_API_LEVEL} -D_FORTIFY_SOURCE=2 --sysroot=${SYSROOT}"
export FFLAGS="$FCFLAGS"
# autoconf Fortran link answers (Termux octave recipe pattern)
export ac_cv_f77_libs="-L${FLANG_RT_DIR} -lFortranRuntime -lFortranDecimal"
# bionic: fortify shims + complex math needed by the Termux-built flang runtime
export LIBS="${LIBS:-} -D_FORTIFY_SOURCE=2 -L${TOOLCHAIN}/lib/clang/19/lib/linux -lclang_rt.builtins-aarch64-android"
export CFLAGS_COMMON="--sysroot=${SYSROOT} -fPIC -D_FORTIFY_SOURCE=2"
echo "[ndk-flang-env] target=$TARGET api=$ANDROID_API_LEVEL"
echo "[ndk-flang-env] CC=$CC"
echo "[ndk-flang-env] FC=$FC (host flang -> $TARGET)"
echo "[ndk-flang-env] flang runtime: $FLANG_RT_DIR/libflang_rt.runtime.a"
