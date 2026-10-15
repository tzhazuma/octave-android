#!/usr/bin/env bash
# Cross-build FFTW3 (single+double, threads, no Fortran) for arm64-v8a Android.
#
# Reproduces the artifacts already in prefix/arm64-v8a/fftw.
# The exact configure invocation is preserved verbatim from the working build's
# config.status so this is a true replay, not a reconstruction.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/env.sh"

VERSION=3.3.10
SRC="$OCTAVE_ANDROID_ROOT/src/fftw-$VERSION"
PFX="$PREFIX_ARM64/fftw"
JOBS="$(sysctl -n hw.ncpu)"

[ -d "$SRC" ] || { echo "missing source: $SRC"; exit 1; }

echo "==> configuring FFTW $VERSION for $TARGET_TRIPLE (API $ANDROID_API)"
cd "$SRC"
./configure \
  --host=aarch64-linux-android \
  --prefix="$PFX" \
  --enable-shared \
  --disable-static \
  --enable-threads \
  --disable-fortran \
  host_alias=aarch64-linux-android \
  CC="$CC_TARGET" \
  CFLAGS="-O2 -fPIC" \
  LDFLAGS="$ANDROID_LDFLAGS" \
  > "$OCTAVE_ANDROID_ROOT/logs/fftw_configure.log" 2>&1

echo "==> make -j$JOBS"
make -j"$JOBS" > "$OCTAVE_ANDROID_ROOT/logs/fftw_make.log" 2>&1

echo "==> make install"
make install > "$OCTAVE_ANDROID_ROOT/logs/fftw_install.log" 2>&1

echo "==> result"
ls -l "$PFX/lib/"*.so
"$READELF" -h "$PFX/lib/libfftw3.so" | grep -E 'Class|Machine|Type'
