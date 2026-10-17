#!/usr/bin/env bash
# Octave route B: cross-compile the pure-C/C++ dependencies Octave core needs.
# Everything installs into prefix/arm64-v8a/<dep>/ and is linked against bionic
# with 16 KiB page alignment.
#
# Usage: scripts/build-deps.sh [zlib pcre2 qhull glpk cxsparse colamd readline ...]
set -euo pipefail

ROOT="$HOME/octave-android"
. "$ROOT/scripts/env.sh"

DL="$ROOT/downloads"
SRC="$ROOT/src"
P="$PREFIX_ARM64"
LOGS="$ROOT/logs"
mkdir -p "$DL" "$SRC" "$LOGS"

unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"   # keep HOSTCC honest
export HOSTCC=/usr/bin/clang

fetch() { # fetch <url> <file>
  local url="$1" f="$DL/$2"
  [ -s "$f" ] || { echo "[fetch] $2"; curl -sSL --max-time 300 -o "$f" "$url"; }
  echo "[fetch] $2 $(stat -f%z "$f") bytes"
}

untar() { # untar <file> <dirname>
  [ -d "$SRC/$2" ] && { echo "[untar] $2 exists"; return; }
  echo "[untar] $2"
  tar -xf "$DL/$1" -C "$SRC"
}

COMMON_CFLAGS="-O2 -fPIC -D_FORTIFY_SOURCE=2"
COMMON_LDFLAGS="$ANDROID_LDFLAGS"

# CRITICAL: autoconf/libtool must use the NDK archiver. Without these it falls
# back to the HOST `ar`/`ranlib`, and Apple's ranlib refuses ELF objects
# ("archive member ... not a mach-o file") while still exiting 0 — leaving a
# 96-byte EMPTY .a that looks like a successful build. This silently broke
# pcre2 on the first attempt.
export AR="$AR_TARGET" RANLIB="$RANLIB_TARGET" STRIP="$STRIP_TARGET" NM="$NM"
export LD="$NDK_BIN/ld.lld"

# ---------------------------------------------------------------- zlib -------
build_zlib() {
  fetch https://zlib.net/fossils/zlib-1.3.1.tar.gz zlib-1.3.1.tar.gz
  untar zlib-1.3.1.tar.gz zlib-1.3.1
  cd "$SRC/zlib-1.3.1"
  CHOST=aarch64-linux-android CC="$CC_TARGET" CFLAGS="$COMMON_CFLAGS" \
    LDFLAGS="$COMMON_LDFLAGS" ./configure --prefix="$P/zlib" --static > "$LOGS/dep_zlib_cfg.log" 2>&1
  # NOTE: a full `make` also builds the example/minigzip *test programs*, which
  # fail to link when cross compiling (their link line lacks -lz ordering).
  # We only need the library, so build it explicitly and install by hand.
  make -j12 libz.a > "$LOGS/dep_zlib_make.log" 2>&1
  mkdir -p "$P/zlib/lib" "$P/zlib/include"
  cp -f libz.a "$P/zlib/lib/"
  cp -f zlib.h zconf.h "$P/zlib/include/"
  echo "[zlib] OK $(ls "$P/zlib/lib")"
}

# ---------------------------------------------------------------- pcre2 ------
build_pcre2() {
  fetch https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.gz pcre2-10.44.tar.gz
  untar pcre2-10.44.tar.gz pcre2-10.44
  cd "$SRC/pcre2-10.44"
  CC="$CC_TARGET" CFLAGS="$COMMON_CFLAGS" LDFLAGS="$COMMON_LDFLAGS" \
    ./configure --host=aarch64-linux-android --prefix="$P/pcre2" \
      --disable-shared --enable-static --enable-pcre2-8 --enable-pcre2-16 \
      --enable-pcre2-32 --disable-pcre2grep --disable-pcre2test \
      --disable-jit > "$LOGS/dep_pcre2_cfg.log" 2>&1
  make -j12 > "$LOGS/dep_pcre2_make.log" 2>&1
  make install >> "$LOGS/dep_pcre2_make.log" 2>&1
  echo "[pcre2] OK $(ls "$P/pcre2/lib")"
}

# ---------------------------------------------------------------- qhull ------
build_qhull() {
  fetch http://www.qhull.org/download/qhull-2020-src-8.0.2.tgz qhull-2020-src-8.0.2.tgz
  untar qhull-2020-src-8.0.2.tgz qhull-2020.2
  cd "$SRC/qhull-2020.2"
  # qhull's Makefile honours these
  make -j12 CC="$CC_TARGET" CXX="$CXX_TARGET" \
    CFLAGS="$COMMON_CFLAGS" CXXFLAGS="$COMMON_CFLAGS" LDFLAGS="$COMMON_LDFLAGS" \
    PREFIX="$P/qhull" DESTDIR= > "$LOGS/dep_qhull_make.log" 2>&1 || true
  # manual install (its install target is unreliable when cross compiling)
  mkdir -p "$P/qhull/lib" "$P/qhull/include/libqhull_r"
  cp -f lib/libqhull_r.a "$P/qhull/lib/" 2>/dev/null || cp -f lib/libqhullstatic_r.a "$P/qhull/lib/libqhull_r.a"
  cp -f src/libqhull_r/libqhull_r.h src/libqhull_r/qhull_ra.h \
        src/libqhull_r/geom_r.h src/libqhull_r/io_r.h src/libqhull_r/mem_r.h \
        src/libqhull_r/merge_r.h src/libqhull_r/poly_r.h src/libqhull_r/random_r.h \
        src/libqhull_r/qset_r.h src/libqhull_r/stat_r.h \
        "$P/qhull/include/libqhull_r/" 2>/dev/null || true
  echo "[qhull] OK $(ls "$P/qhull/lib")"
}

# ---------------------------------------------------------------- glpk -------
build_glpk() {
  fetch https://ftp.gnu.org/gnu/glpk/glpk-5.0.tar.gz glpk-5.0.tar.gz
  untar glpk-5.0.tar.gz glpk-5.0
  cd "$SRC/glpk-5.0"
  CC="$CC_TARGET" CFLAGS="$COMMON_CFLAGS" LDFLAGS="$COMMON_LDFLAGS" \
    ./configure --host=aarch64-linux-android --prefix="$P/glpk" \
      --disable-shared --enable-static > "$LOGS/dep_glpk_cfg.log" 2>&1
  make -j12 > "$LOGS/dep_glpk_make.log" 2>&1
  make install >> "$LOGS/dep_glpk_make.log" 2>&1
  echo "[glpk] OK $(ls "$P/glpk/lib")"
}

# --------------------------------------------------------------- CXSparse ---
build_cxsparse() {
  fetch https://github.com/DrTimothyAldenDavis/SuiteSparse/archive/refs/tags/v7.8.3.tar.gz SuiteSparse-7.8.3.tar.gz
  untar SuiteSparse-7.8.3.tar.gz SuiteSparse-7.8.3
  cd "$SRC/SuiteSparse-7.8.3/CXSparse"
  make -j12 library CC="$CC_TARGET" CFLAGS="$COMMON_CFLAGS" \
    > "$LOGS/dep_cxsparse_make.log" 2>&1 || true
  mkdir -p "$P/suitesparse/lib" "$P/suitesparse/include"
  cp -f Lib/libcxsparse.a "$P/suitesparse/lib/" 2>/dev/null || \
    find . -name 'libcxsparse*.a' -exec cp -f {} "$P/suitesparse/lib/" \; 2>/dev/null || true
  cp -f Include/*.h "$P/suitesparse/include/" 2>/dev/null || true
  echo "[cxsparse] OK $(ls "$P/suitesparse/lib" 2>/dev/null)"
}

build_colamd() {
  cd "$SRC/SuiteSparse-7.8.3/COLAMD"
  make -j12 library CC="$CC_TARGET" CFLAGS="$COMMON_CFLAGS" \
    > "$LOGS/dep_colamd_make.log" 2>&1 || true
  cp -f Lib/libcolamd.a "$P/suitesparse/lib/" 2>/dev/null || \
    find . -name 'libcolamd*.a' -exec cp -f {} "$P/suitesparse/lib/" \; 2>/dev/null || true
  cp -f Include/*.h "$P/suitesparse/include/" 2>/dev/null || true
  echo "[colamd] OK $(ls "$P/suitesparse/lib" 2>/dev/null)"
}

FAILED=""
for d in "$@"; do
  echo "================ build_$d ================"
  if "build_$d"; then :; else
    echo "[$d] FAILED"
    FAILED="$FAILED $d"
  fi
done
echo "DEPS_DONE failed:[$FAILED]"
