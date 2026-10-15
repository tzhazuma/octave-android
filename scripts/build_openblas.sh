#!/usr/bin/env bash
# Cross-build OpenBLAS for arm64-v8a Android with the NDK.
#
# Three modes (OPENBLAS_MODE):
#
#   blas      NOFORTRAN=1 NO_LAPACK=1
#             BLAS + CBLAS only. Fastest, no Fortran anything.
#
#   clapack   NOFORTRAN=1 C_LAPACK=1        <-- the sweet spot for Octave
#             BLAS + full LAPACK built from the f2c-converted C sources that
#             OpenBLAS ships in lapack-netlib/SRC/*.c (dgetrf.c, dpotrf.c,
#             dgesv.c, dsyev.c, ...). 2067 of them. NO Fortran compiler needed.
#             The switch is `ifneq ($(C_LAPACK), 1)` in lapack-netlib/SRC/Makefile.
#
#   fortran   NOFORTRAN=0 FC=flang-new --target=aarch64-linux-android<API>
#             LAPACK from the original .f sources via host flang.
#             NOTE: OpenBLAS's f_check probe compiles AND RUNS test binaries to
#             learn the compiler's ABI, which cannot work when cross-compiling.
#             Expect to have to pre-seed Makefile.conf for this mode.
#
# HOSTCC is pinned to Apple clang on purpose -- see the PATH trap note in env.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/env.sh"

VERSION="${OPENBLAS_VERSION:-0.3.34}"
MODE="${OPENBLAS_MODE:-clapack}"
# OPENBLAS_SRC lets a caller build in an ISOLATED copy of the tree. Use it:
# OpenBLAS's build writes .o files in place, so two concurrent builds sharing one
# tree corrupt each other (we lost a .so link to exactly that: a Fortran-built
# second_NONE.o from another build collided with our C-built second_INT_ETIME.o).
SRC="${OPENBLAS_SRC:-$OCTAVE_ANDROID_ROOT/src/OpenBLAS-$VERSION}"
PFX="$PREFIX_ARM64/openblas"
LOG="$OCTAVE_ANDROID_ROOT/logs/openblas_${MODE}_make.log"
JOBS="$(sysctl -n hw.ncpu)"

# TARGET: ARMV8 is the portable baseline (one binary runs on any armv8-a).
# Device here is MediaTek MT8799 (Cortex-X4 + Cortex-A720, SVE2). Moving to a
# tuned core (NEOVERSEV1 / CORTEXA76) is a later perf step, not a correctness one.
TARGET_CORE="${OPENBLAS_TARGET:-ARMV8}"

[ -d "$SRC" ] || { echo "missing source: $SRC"; exit 1; }
MAKE_BIN="$(command -v gmake || command -v make)"

case "$MODE" in
  blas)    EXTRA=(NOFORTRAN=1 NO_LAPACK=1 NO_LAPACKE=1) ;;
  clapack) EXTRA=(NOFORTRAN=1 C_LAPACK=1) ;;
  fortran) EXTRA=(NOFORTRAN=0 FC="$FLANG_BIN"
                  FFLAGS="--target=$TARGET_TRIPLE$ANDROID_API -fPIC -O2") ;;
  *) echo "unknown OPENBLAS_MODE=$MODE (blas|clapack|fortran)"; exit 2 ;;
esac

echo "==> OpenBLAS $VERSION  mode=$MODE  TARGET=$TARGET_CORE  -> $TARGET_TRIPLE"
echo "=== OpenBLAS build start $(date)  mode=$MODE ===" > "$LOG"
cd "$SRC"
"$MAKE_BIN" -j"$JOBS" \
  OSNAME=Android ARCH=arm64 TARGET="$TARGET_CORE" \
  CROSS=1 HOSTCC="$HOSTCC" \
  CC="$CC_TARGET" AR="$AR_TARGET" RANLIB="$RANLIB_TARGET" \
  "${EXTRA[@]}" \
  USE_OPENMP=0 BINARY=64 DYNAMIC_ARCH=0 \
  COMMON_OPT="-O2 -fPIC" \
  LDFLAGS="$ANDROID_LDFLAGS" \
  PREFIX="$PFX" \
  >> "$LOG" 2>&1 || { echo "BUILD FAILED -- tail of $LOG:"; tail -30 "$LOG"; exit 1; }
echo "OPENBLAS_MAKE_RC=0" >> "$LOG"

# OSNAME=Android must be repeated here, otherwise install uses Darwin naming
# and creates .dylib symlinks instead of .so ones.
echo "==> make install PREFIX=$PFX"
"$MAKE_BIN" OSNAME=Android ARCH=arm64 TARGET="$TARGET_CORE" \
  NOFORTRAN=1 PREFIX="$PFX" install >> "$LOG" 2>&1 || true
echo "=== done $(date) ===" >> "$LOG"

echo "==> result"
ls -l "$SRC"/libopenblas*.so* 2>/dev/null
echo "==> installed"
ls -l "$PFX/lib/"*.so* 2>/dev/null || echo "(no .so in prefix -- check $LOG)"
