#!/usr/bin/env bash
# ROUTE B FORTRAN GATE -- decisive test.
# Question: can we compile Fortran to aarch64-linux-android from this macOS host
# without gfortran and without building a cross-flang ourselves?
# Answer: YES -- Homebrew flang-new (LLVM Flang) is target-agnostic.
set -uo pipefail
ROOT="$HOME/octave-android"; G="$ROOT/spike/fortran-gate"
TC="$HOME/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64"
FLANG=/opt/homebrew/bin/flang-new
RT="$ROOT/prefix/arm64-v8a/flang-runtime"
BUILTINS="$TC/lib/clang/19/lib/linux/libclang_rt.builtins-aarch64-android.a"
cd "$G"

echo "### 0. toolchain identity"
$FLANG --version | head -2
"$TC/bin/aarch64-linux-android24-clang" --version | head -1

echo; echo "### 1. pure-computation Fortran -> aarch64 (classic f77 ABI)"
$FLANG --target=aarch64-linux-android21 --sysroot="$TC/sysroot" -c fscale.f90 -o fscale_android.o
file fscale_android.o
echo "-- exported symbols (must be fscale_ / fdot_ for LAPACK/ARPACK compat):"
"$TC/bin/llvm-nm" fscale_android.o
echo "-- undefined symbols (none => no runtime needed):"
"$TC/bin/llvm-nm" -u fscale_android.o; echo "   [end]"

echo; echo "### 2. link with NDK clang (API 21 static + PIE)"
"$TC/bin/aarch64-linux-android21-clang" driver.c fscale_android.o -o fortran_gate_android
"$TC/bin/aarch64-linux-android21-clang" -static driver.c fscale_android.o -o fortran_gate_android_static

echo; echo "### 3. runtime-using Fortran (matmul + intrinsics + COMPLEX*16 + formatted WRITE)"
$FLANG --target=aarch64-linux-android21 --sysroot="$TC/sysroot" -c rtgate.f90 -o rtgate_android.o
echo "-- runtime ABI surface required:"
"$TC/bin/llvm-nm" -u rtgate_android.o | sed 's/^ *//'

echo; echo "### 4. link runtime gate (Termux flang aarch64 runtime + NDK compiler-rt)"
echo "-- API 21 PIE FAILS (bionic fortify gaps) -- recording the failure:"
"$TC/bin/aarch64-linux-android21-clang" rtdriver.c rtgate_android.o "$RT/libflang_rt.runtime.a" "$BUILTINS" -lm -o /dev/null 2>&1 | grep -E "undefined symbol" | sort -u
echo "-- API 24 + -D_FORTIFY_SOURCE=2 FIXES it:"
"$TC/bin/aarch64-linux-android24-clang" -D_FORTIFY_SOURCE=2 rtdriver.c rtgate_android.o "$RT/libflang_rt.runtime.a" "$BUILTINS" -lm -o rtgate_api24 && echo "   PIE link OK"
"$TC/bin/aarch64-linux-android21-clang" -static rtdriver.c rtgate_android.o "$RT/libflang_rt.runtime.a" "$BUILTINS" -lm -o rtgate_static && echo "   static link OK"

echo; echo "### 5. numeric cross-validation vs host gfortran"
/opt/homebrew/bin/gfortran rtgate.f90 rtdriver.c -o rtgate_host 2>/dev/null && { printf "host gfortran : "; ./rtgate_host; }
