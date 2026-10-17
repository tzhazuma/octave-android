#!/usr/bin/env bash
# Route B: build the installable APK that packages the cross-compiled native
# numerical stack (OpenBLAS / FFTW / ARPACK / qrupdate) plus a JNI probe.
#
# Prereqs (all already produced by the other scripts in this directory):
#   prefix/arm64-v8a/openblas/lib/libopenblas_armv8p-r0.3.34.so
#   prefix/arm64-v8a/fftw/lib/libfftw3.so (+ _threads)
#   src/arpack-ng-3.9.1/SRC/.libs/libarpack.so
#   src/qrupdate-ng-1.3.1  (built out-of-tree, see STATUS.md 3.7)
#
# Usage:  scripts/build-apk.sh [--install]
set -euo pipefail

ROOT="$HOME/octave-android"
APP="$ROOT/android-app"
TC="$HOME/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64"
WRAP="$ROOT/scripts/toolbin/aarch64-linux-android24-flang-new"
JL="$APP/app/src/main/jniLibs/arm64-v8a"
P="$ROOT/prefix/arm64-v8a"
GRADLE="$HOME/.gradle/wrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj/gradle-9.4.1/bin/gradle"

# JDK 27 is too new for AGP (class file major version 71); use 21.
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}"

echo "== 1. stage native libraries into jniLibs =="
mkdir -p "$JL"
cp -f "$P/openblas/lib/libopenblas_armv8p-r0.3.34.so" "$JL/libopenblas.so"
cp -f "$P/fftw/lib/libfftw3.so"                        "$JL/libfftw3.so"
cp -f "$P/fftw/lib/libfftw3_threads.so"                "$JL/libfftw3_threads.so"
cp -f "$ROOT/src/arpack-ng-3.9.1/SRC/.libs/libarpack.so" "$JL/libarpack.so"
# qrupdate must carry SONAME=libqrupdate.so (not .so.1) so the DT_NEEDED of
# liboctdemo.so matches the packaged filename; relinked from the CMake objects.
if [ -d /tmp/qrbuild28 ]; then
  # shellcheck disable=SC2046
  "$WRAP" -shared -Wl,-soname,libqrupdate.so -Wl,-z,max-page-size=16384 \
    -o "$JL/libqrupdate.so" \
    $(find /tmp/qrbuild28 -path "*CMakeFiles/qrupdate.dir*" -name "*.o") \
    -L"$P/openblas/lib" -lopenblas
fi

echo "== 2. build liboctdemo.so (Fortran via flang wrapper, C via NDK clang) =="
cd "$APP/app/src/main/jni"
# shellcheck disable=SC2046
"$WRAP" -fPIC -O2 -shared -Wl,-z,max-page-size=16384 -Wl,--allow-shlib-undefined \
  -I"$TC/sysroot/usr/include" -o "$JL/liboctdemo.so" \
  octdemo.c arpack_wrap.f arpack_util/*.f \
  -L"$JL" -lopenblas -lfftw3 -larpack -lqrupdate

echo "== 3. verify 16 KiB page alignment on every packaged .so =="
for f in "$JL"/*.so; do
  a=$("$TC/bin/llvm-readelf" -l "$f" | awk '/LOAD/{print $NF; exit}')
  printf '   %-26s %s\n' "$(basename "$f")" "$a"
  [ "$a" = "0x4000" ] || { echo "   !! $f is not 16 KiB aligned"; exit 1; }
done

echo "== 4. gradle assembleDebug =="
cd "$APP"
"$GRADLE" -q assembleDebug
APK="$APP/app/build/outputs/apk/debug/app-debug.apk"
ls -la "$APK"

if [ "${1:-}" = "--install" ]; then
  echo "== 5. install =="
  ADB="$HOME/Library/Android/sdk/platform-tools/adb"
  DEV="${DEVICE:-$("$ADB" devices | awk '/\tdevice$/{print $1; exit}')}"
  echo "   device: $DEV"
  "$ADB" -s "$DEV" install -r -t "$APK"
fi
echo "OK: $APK"
