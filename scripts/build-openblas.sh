#!/usr/bin/env bash
# Route B milestone 2: cross-compile OpenBLAS for aarch64-linux-android with
# LLVM Flang (Fortran ENABLED -- the Fortran gate is open, so no NOFORTRAN=1 fallback).
set -euo pipefail
ROOT="$HOME/octave-android"
TC="$HOME/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64"
WRAP="$ROOT/scripts/toolbin/aarch64-linux-android24-flang-new"
RT="$ROOT/prefix/arm64-v8a/flang-runtime"
SRC="$ROOT/src/OpenBLAS-0.3.34"
PREFIX="$ROOT/prefix/arm64-v8a/openblas"
mkdir -p "$PREFIX"
cd "$SRC"

# OpenBLAS auto-adds -lgfortran only for GFORTRAN; for FLANGNEW we must supply the
# flang runtime ourselves, plus bionic fortify shims + compiler-rt builtins
# (__divdc3 & friends for COMPLEX arithmetic).
FEXTRALIB="-L$RT -lFortranRuntime -lFortranDecimal -L$TC/lib/clang/19/lib/linux -lclang_rt.builtins-aarch64-android -lm"
LDFLAGS_EXTRA="-D_FORTIFY_SOURCE=2"

make -j"$(sysctl -n hw.ncpu)" \
  TARGET=ARMV8 BINARY=64 DYNAMIC_ARCH=0 \
  CROSS=1 \
  CC="$TC/bin/aarch64-linux-android24-clang" \
  FC="$WRAP" \
  HOSTCC=cc \
  AR="$TC/bin/llvm-ar" \
  RANLIB="$TC/bin/llvm-ranlib" \
  NOFORTRAN=0 \
  USE_OPENMP=0 \
  NUM_THREADS=64 \
  PREFIX="$PREFIX" \
  FEXTRALIB="$FEXTRALIB" \
  LDFLAGS="$LDFLAGS_EXTRA" \
  libs shared 2>&1
