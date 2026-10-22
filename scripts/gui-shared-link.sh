#!/bin/sh
# Relink octave-gui as libOctaveGui_arm64-v8a.so -- the production link.
#
# This is the canonical link step (the same one as /tmp/gui-shared-link.sh),
# kept in-tree so the build is reproducible.  It links src/main-gui.cc's
# main() directly; the startup probe in gui-probe/ is NOT part of this build.
#
# Usage: scripts/gui-shared-link.sh [--deploy]
#   --deploy copies the result over android-gui-app/jniLibs/arm64-v8a/.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/src/octave-11.3.0"
BUILD="$ROOT/build/gui-vanilla"
QT="$HOME/freecad-android/Qt/6.8.3/android_arm64_v8a"
NDK="$HOME/Library/Android/sdk/ndk/28.2.13676358"
PREBUILT="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
CXX="$PREBUILT/bin/aarch64-linux-android24-clang++"

mkdir -p "$BUILD"
cd "$SRC"

echo "== linking production .so =="
"$CXX" -fPIC -pthread -Wall -W -Wshadow -Woverloaded-virtual -Wold-style-cast \
    -Wformat -Wpointer-arith -Wwrite-strings -Wcast-align -Wcast-qual \
    -O2 -fPIC \
    -L"$QT/lib" \
    -L"$ROOT/prefix/arm64-v8a/zlib/lib" \
    -L"$ROOT/prefix/arm64-v8a/fftw/lib" \
    -L"$ROOT/prefix/arm64-v8a/pcre2/lib" \
    -L"$ROOT/src/gl4es/lib" \
    src/octave_gui-main-gui.o \
    src/octave_gui-octave-build-info.o \
    -Llibgui/.libs -loctgui \
    -Llibmex/.libs -loctmex \
    -Llibinterp/.libs -loctinterp \
    -Lliboctave/.libs -loctave \
    -Llibgnu/.libs -lgnu \
    -L"$QT/lib" \
    -lQt6Core_arm64-v8a -lQt6Gui_arm64-v8a -lQt6Widgets_arm64-v8a \
    -lQt6Network_arm64-v8a -lQt6PrintSupport_arm64-v8a \
    -lQt6OpenGL_arm64-v8a -lQt6OpenGLWidgets_arm64-v8a \
    -lQt6Help_arm64-v8a -lQt6Xml_arm64-v8a -lQt6Core5Compat_arm64-v8a \
    -lz -lfftw3_threads -lfftw3 -lfftw3f_threads -lfftw3f \
    -lGL -lGLU \
    -L"$ROOT/prefix/arm64-v8a/openblas/lib" -lopenblas \
    -L"$ROOT/prefix/arm64-v8a/openblas/lib" -lopenblas \
    -L"$ROOT/prefix/arm64-v8a/openblas/lib" -lopenblas \
    -lpcre2 \
    -L"$ROOT/prefix/arm64-v8a/flang-runtime" -lflang_rt.runtime \
    -lm \
    -L"$ROOT/prefix/arm64-v8a/libiconv/lib" -liconv \
    -shared -Wl,--export-dynamic -Wl,--allow-shlib-undefined \
    -o "$BUILD/libOctaveGui_arm64-v8a.so"

echo "== built $BUILD/libOctaveGui_arm64-v8a.so =="

if [ "${1:-}" = "--deploy" ]; then
    cp "$BUILD/libOctaveGui_arm64-v8a.so" \
       "$ROOT/android-gui-app/jniLibs/arm64-v8a/libOctaveGui_arm64-v8a.so"
    echo "== deployed to jniLibs =="
fi
