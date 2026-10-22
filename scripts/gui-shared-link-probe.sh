#!/bin/sh
# Link libOctaveGui_arm64-v8a.so with the startup probe.
#
# This is the original /tmp/gui-shared-link.sh command plus three changes:
#   1. Octave's main symbol is renamed to octave_real_main with llvm-objcopy,
#      so gui-probe/gui-main-probe.cc can provide the real main() and log.
#   2. octave::qt_application's constructor and execute() are hooked with
#      -Wl,--wrap so we learn whether QApplication construction or the GUI
#      start-up is what dies.
#   3. the result is written under build/gui-probe/ for inspection.
#
# Usage: scripts/gui-shared-link-probe.sh [--deploy]
#   --deploy copies the result over android-gui-app/jniLibs/arm64-v8a/.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/src/octave-11.3.0"
BUILD="$ROOT/build/gui-probe"
QT="$HOME/freecad-android/Qt/6.8.3/android_arm64_v8a"
NDK="$HOME/Library/Android/sdk/ndk/28.2.13676358"
PREBUILT="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
CXX="$PREBUILT/bin/aarch64-linux-android24-clang++"
OBJCOPY="$PREBUILT/bin/llvm-objcopy"

WRAP_CTOR='_ZN6octave14qt_applicationC1ERKNSt6__ndk112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_S9_iPPc'
WRAP_EXEC='_ZN6octave14qt_application7executeEv'

mkdir -p "$BUILD"

echo "== renaming Octave main() =="
"$OBJCOPY" --redefine-sym main=octave_real_main \
    "$SRC/src/octave_gui-main-gui.o" "$BUILD/octave-main-renamed.o"

echo "== compiling startup probe =="
"$CXX" -std=c++17 -fPIC -O2 -Wall -DQT_CORE_LIB \
    -I"$QT/include" -I"$QT/include/QtCore" \
    -c "$ROOT/gui-probe/gui-main-probe.cc" \
    -o "$BUILD/gui-main-probe.o"

cd "$SRC"

echo "== linking probe .so =="
"$CXX" -fPIC -pthread -Wall -W -Wshadow -Woverloaded-virtual -Wold-style-cast \
    -Wformat -Wpointer-arith -Wwrite-strings -Wcast-align -Wcast-qual \
    -O2 -fPIC \
    -L"$QT/lib" \
    -L"$ROOT/prefix/arm64-v8a/zlib/lib" \
    -L"$ROOT/prefix/arm64-v8a/fftw/lib" \
    -L"$ROOT/prefix/arm64-v8a/pcre2/lib" \
    -L"$ROOT/src/gl4es/lib" \
    -Wl,--wrap="$WRAP_CTOR" \
    -Wl,--wrap="$WRAP_EXEC" \
    "$BUILD/gui-main-probe.o" \
    "$BUILD/octave-main-renamed.o" \
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
    -llog -ldl \
    -shared -Wl,--export-dynamic -Wl,--allow-shlib-undefined \
    -o "$BUILD/libOctaveGui_arm64-v8a.so"

echo "== built $BUILD/libOctaveGui_arm64-v8a.so =="
"$PREBUILT/bin/llvm-nm" -D --defined-only "$BUILD/libOctaveGui_arm64-v8a.so" \
    | grep -E ' (main|octave_real_main)$' || true

if [ "${1:-}" = "--deploy" ]; then
    cp "$BUILD/libOctaveGui_arm64-v8a.so" \
       "$ROOT/android-gui-app/jniLibs/arm64-v8a/libOctaveGui_arm64-v8a.so"
    echo "== deployed to jniLibs =="
fi
