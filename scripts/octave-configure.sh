#!/usr/bin/env bash
# Octave route B: apply Termux's bionic patches and run the cross configure.
#
# Provenance: downloads/termux-octave-build.sh is Termux's own recipe (fetched
# via `gh api`), and our octave-11.3.0.tar.xz sha256 matches their pin exactly
# (2b80f3149b2de6d1f4f2fcb4fe6515a17eb363b52111bf57b90f37bf6f5e12e1).
set -uo pipefail

ROOT="$HOME/octave-android"
SRC="$ROOT/src/octave-11.3.0"
P="$ROOT/prefix/arm64-v8a"
LOGS="$ROOT/logs"
NDK="$HOME/Library/Android/sdk/ndk/28.2.13676358"
TC="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
WRAP="$ROOT/scripts/toolbin/aarch64-linux-android24-flang-new"
FLANG_RT_DIR="$P/flang-runtime"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY

cd "$SRC" || { echo "NO SOURCE"; exit 1; }

echo "=== 1. apply Termux bionic patches ==="
for p in 0001-fix-hardcoded-paths.patch 0002-append-rpath-flag-to-pkg-config-files.patch 0003-undefine-the-macro-in-pwd.h.patch; do
  f="$ROOT/downloads/termux-patches/$p"
  if patch -p1 --dry-run -s -f < "$f" >/dev/null 2>&1; then
    patch -p1 -s < "$f" && echo "  applied $p"
  else
    echo "  SKIP $p (already applied or does not fit)"
  fi
done

echo "=== 2. bionic ac_cv answers (from Termux's recipe) ==="
AC_CV=(
  ac_cv_header_glob_h=no
  ac_cv_func_endpwent=no ac_cv_func_getegid=no
  ac_cv_func_geteuid=no ac_cv_func_getgrent=no ac_cv_func_getgrgid=no
  ac_cv_func_getgrnam=no ac_cv_func_getpwent=no ac_cv_func_getpwnam=no
  ac_cv_func_getpwnam_r=no ac_cv_func_getpwuid=no ac_cv_func_setgrent=no
  ac_cv_func_setpwent=no ac_cv_func_setpwuid=no
  gl_cv_cc_visibility=no
  ac_cv_f77_libs="-L$FLANG_RT_DIR -lflang_rt.runtime"
)

export CC="$TC/bin/aarch64-linux-android24-clang"
export CXX="$TC/bin/aarch64-linux-android24-clang++"
export FC="$WRAP" F77="$WRAP"
export AR="$TC/bin/llvm-ar" RANLIB="$TC/bin/llvm-ranlib"
export STRIP="$TC/bin/llvm-strip" NM="$TC/bin/llvm-nm"

INCS="-I$P/zlib/include -I$P/pcre2/include -I$P/openblas/include -I$P/fftw/include -I$P/qhull/include -I$P/glpk/include -I$P/suitesparse/include -I$P/fastfloat/include -I$P/libiconv/include"
LIBS_DIRS="-L$P/zlib/lib -L$P/pcre2/lib -L$P/openblas/lib -L$P/fftw/lib -L$P/qhull/lib -L$P/glpk/lib -L$P/suitesparse/lib -L$P/libiconv/lib"
BUILTINS="$TC/lib/clang/19/lib/linux/libclang_rt.builtins-aarch64-android.a"

# Keep pkg-config from discovering HOST (macOS/Homebrew) libraries.
export PKG_CONFIG_LIBDIR="$P/zlib/lib/pkgconfig:$P/pcre2/lib/pkgconfig:$P/openblas/lib/pkgconfig:$P/fftw/lib/pkgconfig:$P/glpk/lib/pkgconfig:$P/qhull/lib/pkgconfig"
export PKG_CONFIG_PATH=""

echo "=== 3. configure ==="
./configure \
  --host=aarch64-linux-android --build=aarch64-apple-darwin \
  --prefix="$P/octave" \
  --without-x --disable-java --disable-openmp --disable-docs --disable-readline \
  --enable-link-all-dependencies \
  --enable-fortran-calling-convention=f2c \
  --disable-rapidjson \
  --with-blas="-L$P/openblas/lib -lopenblas" \
  --with-lapack="-L$P/openblas/lib -lopenblas" \
  --without-openssl \
  --with-libiconv-prefix="$P/libiconv" \
  --without-curl --without-hdf5 --without-sundials --without-spqr \
  --without-amd --without-ccolamd --without-colamd --without-cholmod \
  --without-cxsparse --without-umfpack --without-suitesparseconfig \
  --without-freetype --without-fontconfig --without-opengl --without-fltk \
  --without-qt --without-magick --without-portaudio --without-sndfile \
  --without-alsa --without-wayland-client --without-qrupdate --without-arpack \
  --with-z-includedir="$P/zlib/include" --with-z-libdir="$P/zlib/lib" \
  --with-pcre2-includedir="$P/pcre2/include" --with-pcre2-libdir="$P/pcre2/lib" \
  --with-qhull_r-includedir="$P/qhull/include" --with-qhull_r-libdir="$P/qhull/lib" \
  --with-glpk-includedir="$P/glpk/include" --with-glpk-libdir="$P/glpk/lib" \
  "${AC_CV[@]}" \
  CPPFLAGS="$INCS -D_FORTIFY_SOURCE=2" \
  CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" \
  LDFLAGS="$LIBS_DIRS -Wl,-z,max-page-size=16384 -Wl,-Bsymbolic -Wl,--allow-multiple-definition" \
  LIBS="$BUILTINS -lm" \
  2>&1 | tee "$LOGS/octave_configure_full.log"

echo "CONFIGURE_RC=${PIPESTATUS[0]}"
