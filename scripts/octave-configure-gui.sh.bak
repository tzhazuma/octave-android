#!/usr/bin/env bash
# Reconfigure the Octave build with the Qt GUI enabled.
#
# Octave's configure normally finds Qt through pkg-config, and the Qt-for-Android kit
# ships CMake files but no .pc files -- so pkg-config would never see it. configure has
# an escape hatch for exactly this (m4/acinclude.m4, "Don't use pkg-config but assume
# the provided flags are correct"): give it QT_CPPFLAGS, QT_LIBS and QT_LDFLAGS
# directly and it uses them untouched.
#
# moc/uic/rcc must be HOST binaries of the same Qt version; a Qt for Android install
# keeps them in the host kit, not in the android directory. Here they come from
# ~/Qt-host/6.8.3/macos/libexec (aqt install-qt mac desktop 6.8.3 clang_64
# --archives qtbase icu).
#
# QScintilla is disabled: it is not part of the Qt kit and the editor falls back to a
# plain text widget without it.
#
# Everything else is byte-for-byte the configure line recorded in config.log for the
# console build -- same bionic ac_cv answers, same dependency prefixes -- so that the
# already-built liboctave/liboctinterp stay valid.
set -uo pipefail

ROOT="$HOME/octave-android"
SRC="$ROOT/src/octave-11.3.0"
P="$ROOT/prefix/arm64-v8a"
NDK="$HOME/Library/Android/sdk/ndk/28.2.13676358"
TC="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
WRAP="$ROOT/scripts/toolbin/aarch64-linux-android24-flang-new"
FLANG_RT_DIR="$P/flang-runtime"
QT="$HOME/freecad-android/Qt/6.8.3/android_arm64_v8a"
QTH="$HOME/Qt-host/6.8.3/macos"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

[ -x "$QTH/libexec/moc" ] || { echo "missing host moc at $QTH/libexec/moc"; exit 1; }
[ -d "$QT/include/QtWidgets" ] || { echo "missing Qt android kit at $QT"; exit 1; }

cd "$SRC" || exit 1

AC_CV=(
  ac_cv_header_glob_h=no
  ac_cv_func_endpwent=no ac_cv_func_getegid=no
  ac_cv_func_geteuid=no ac_cv_func_getgrent=no ac_cv_func_getgrgid=no
  ac_cv_func_getgrnam=no ac_cv_func_getpwent=no ac_cv_func_getpwnam=no
  ac_cv_func_getpwnam_r=no ac_cv_func_getpwuid=no ac_cv_func_setgrent=no
  ac_cv_func_setpwent=no ac_cv_func_setpwuid=no
  gl_cv_cc_visibility=no
  "ac_cv_f77_libs=-L$FLANG_RT_DIR -lflang_rt.runtime"
  # autoconf's AC_SEARCH_LIBS(openpty) emits a C++ test into a .c file here and fails for
  # that reason alone ("unknown type name 'namespace'"), not because bionic lacks the
  # function -- bionic has openpty in libc since API 23. Octave's terminal needs it.
  "ac_cv_search_openpty=none required"
)

INCS="-I$P/zlib/include -I$P/pcre2/include -I$P/openblas/include -I$P/fftw/include -I$P/qhull/include -I$P/glpk/include -I$P/suitesparse/include -I$P/fastfloat/include -I$P/libiconv/include"
QT_INCS=""
for m in QtCore QtGui QtWidgets QtNetwork QtPrintSupport QtOpenGL QtOpenGLWidgets QtHelp QtXml QtCore5Compat; do
  QT_INCS="$QT_INCS -I$QT/include/$m"
done
QT_LIBS_FLAGS="-L$QT/lib"
for m in Core Gui Widgets Network PrintSupport OpenGL OpenGLWidgets Help Xml Core5Compat; do
  QT_LIBS_FLAGS="$QT_LIBS_FLAGS -lQt6${m}_arm64-v8a"
done

export CC="$TC/bin/aarch64-linux-android24-clang"
export CXX="$TC/bin/aarch64-linux-android24-clang++"
export FC="$WRAP" F77="$WRAP"
export AR="$TC/bin/llvm-ar" RANLIB="$TC/bin/llvm-ranlib"
export STRIP="$TC/bin/llvm-strip" NM="$TC/bin/llvm-nm"
export PKG_CONFIG_LIBDIR="$P/zlib/lib/pkgconfig:$P/pcre2/lib/pkgconfig:$P/openblas/lib/pkgconfig:$P/fftw/lib/pkgconfig:$P/glpk/lib/pkgconfig:$P/qhull/lib/pkgconfig"
export PKG_CONFIG_PATH=""

echo "== configure with Qt GUI =="
# Exported (not just trailing assignments) because the Qt probe reads the environment.
export QT_CPPFLAGS="-I$QT/include$QT_INCS"
export QT_LIBS="$QT_LIBS_FLAGS"
export QT_LDFLAGS="-L$QT/lib"
export QT_HOST_BINS="$QTH/bin"
export QT_HOST_LIBEXECS="$QTH/libexec"
./configure \
  --host=aarch64-linux-android --build=aarch64-apple-darwin \
  --prefix="$P/octave" \
  --without-x --disable-java --disable-openmp --disable-docs --disable-readline \
  --enable-link-all-dependencies --enable-fortran-calling-convention=f2c \
  --disable-rapidjson \
  --with-blas="-L$P/openblas/lib -lopenblas" \
  --with-lapack="-L$P/openblas/lib -lopenblas" \
  --without-openssl --with-libiconv-prefix="$P/libiconv" \
  --without-curl --without-hdf5 --without-sundials \
  --without-spqr --without-amd --without-ccolamd --without-colamd --without-cholmod \
  --without-cxsparse --without-umfpack --without-suitesparseconfig \
  --without-freetype --without-fontconfig --without-opengl --without-fltk \
  --with-qt=6 --enable-gui --without-qscintilla \
  --without-magick --without-portaudio --without-sndfile --without-alsa \
  --without-wayland-client --without-qrupdate --without-arpack \
  --with-z-includedir="$P/zlib/include" --with-z-libdir="$P/zlib/lib" \
  --with-pcre2-includedir="$P/pcre2/include" --with-pcre2-libdir="$P/pcre2/lib" \
  --with-qhull_r-includedir="$P/qhull/include" --with-qhull_r-libdir="$P/qhull/lib" \
  --with-glpk-includedir="$P/glpk/include" --with-glpk-libdir="$P/glpk/lib" \
  "${AC_CV[@]}" \
  "CPPFLAGS=$INCS -D_FORTIFY_SOURCE=2" \
  "CFLAGS=-O2 -fPIC" \
  "CXXFLAGS=-O2 -fPIC" \
  "QT_CPPFLAGS=-I$QT/include$QT_INCS" \
  "QT_LIBS=$QT_LIBS_FLAGS" \
  "QT_LDFLAGS=-L$QT/lib" \
  "QT_HOST_BINS=$QTH/bin" \
  "QT_HOST_LIBEXECS=$QTH/libexec"
RC=$?
echo "CONFIGURE_RC=$RC"
exit $RC
