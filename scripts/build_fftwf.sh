#!/usr/bin/env bash
# Octave needs BOTH FFTW3 (double) and FFTW3F (single precision) -- the float
# library is what `fft` on single-precision data uses. A single FFTW build
# produces only one of the two, so the float pass is built out-of-tree into the
# SAME prefix (so libfftw3f.so lands next to libfftw3.so).
set -euo pipefail
ROOT="$HOME/octave-android"
. "$ROOT/scripts/env.sh"
P="$PREFIX_ARM64"
LOGS="$ROOT/logs"
# FFTW refuses out-of-tree builds ("source directory already configured"),
# so the float pass uses its own freshly-extracted copy of the tree.
SRCDIR="$ROOT/src/fftw-3.3.10-float"
BUILD="$ROOT/src/fftw-3.3.10-float"
# NOTE: the fftw tarball lives in src/, not downloads/ (easy to get wrong).
FFTW_TARBALL="$ROOT/src/fftw-3.3.10.tar.gz"
[ -d "$SRCDIR" ] || { tar xzf "$FFTW_TARBALL" -C "$ROOT/src" && mv "$ROOT/src/fftw-3.3.10" "$SRCDIR"; }
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# CRITICAL (same trap as build-deps.sh): without these, autoconf/libtool falls
# back to the HOST ar/ranlib. Apple's ranlib rejects ELF objects, so FFTW's
# convenience archives (kernel/libkernel.la, dft/libdft.la, ...) end up
# unreadable and the final .so links to an EMPTY 5 KB stub with zero symbols --
# while every command still reports success.
export AR="$AR_TARGET" RANLIB="$RANLIB_TARGET" STRIP="$STRIP_TARGET" NM="$NM"

[ -d "$SRCDIR" ] || { echo "no fftw source"; exit 1; }
mkdir -p "$BUILD"
cd "$BUILD"

if [ ! -f config.status ]; then
  "$SRCDIR/configure" --host=aarch64-linux-android \
    --prefix="$P/fftw" \
    --enable-shared --disable-static --enable-threads --disable-fortran \
    --enable-float \
    host_alias=aarch64-linux-android \
    CC="$CC_TARGET" \
    CFLAGS="-O2 -fPIC" \
    LDFLAGS="$ANDROID_LDFLAGS" > "$LOGS/fftwf_configure.log" 2>&1
fi
echo "CONFIGURE done"
make -j12 > "$LOGS/fftwf_make.log" 2>&1
echo "MAKE_RC=$?"
make install >> "$LOGS/fftwf_make.log" 2>&1
echo "INSTALL_RC=$?"
ls -la "$P/fftw/lib" | grep -E 'fftw3f|fftw3'
"$READELF" -d "$P/fftw/lib/libfftw3f.so" | grep -E 'SONAME|NEEDED'
echo "FFTWF_DONE"
