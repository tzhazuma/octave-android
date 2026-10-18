#!/usr/bin/env bash
# Stage the cross-compiled Octave tree into the APK.
#
# Everything under assets/oct is generated from prefix/arm64-v8a (and the gnuplot
# build), so none of it is committed: 75 MB of binaries in git would be dead weight
# that goes stale the moment the prefix is rebuilt.
#
# Two details here are not cosmetic:
#
#  1. The executables (octave-cli, gnuplot) go to jniLibs, not assets. Android 10
#     and later refuse execve() on app_data_file -- a file under filesDir with mode
#     0755 still fails with "error=13, Permission denied" -- but the APK's native
#     library directory is executable. They ship as liboctavecli.so / libgnuplot.so
#     and OctaveRuntime runs them from nativeLibraryDir.
#
#  2. The install tree is full of libtool symlinks (bin/octave-cli -> octave-cli-11.3.0).
#     Gradle silently drops symlinked assets, so the binaries are materialised first.
set -euo pipefail

ROOT="$HOME/octave-android"
A="$ROOT/android-app/app/src/main/assets/oct"
JL="$ROOT/android-app/app/src/main/jniLibs/arm64-v8a"
P="$ROOT/prefix/arm64-v8a"
NDK="$HOME/Library/Android/sdk/ndk/28.2.13676358"
TC="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
GP="$ROOT/src/gnuplot-6.0.0/src/gnuplot"

for f in "$P/octave/bin/octave-cli-11.3.0" "$P/octave/lib/octave/11.3.0/liboctinterp.so" "$GP"; do
  [ -e "$f" ] || { echo "missing $f -- build Octave and gnuplot first"; exit 1; }
done

echo "== 1. octave install tree =="
rm -rf "$A"
mkdir -p "$A/octave" "$A/deps" "$A/octave/lib/octave"
cp -R "$P/octave/bin" "$A/octave/"
cp -R "$P/octave/lib/octave/11.3.0" "$A/octave/lib/octave/"
cp -R "$P/octave/share" "$A/octave/"
# Static archives and libtool metadata are build-time only.
rm -f "$A/octave/lib/octave/11.3.0"/*.la "$A/octave/lib/octave/11.3.0"/*.a
find "$A/octave" -name '*.so' -exec "$TC/bin/llvm-strip" --strip-unneeded {} \;

echo "== 2. materialise the libtool symlinks =="
for name in octave-cli octave octave-config mkoctfile; do
  f="$A/octave/bin/$name"
  if [ -L "$f" ]; then
    target=$(readlink "$f")
    rm -f "$f"
    cp "$A/octave/bin/$target" "$f"
    chmod 755 "$f"
  fi
done

echo "== 3. executables as native libraries =="
mkdir -p "$JL"
cp -f "$A/octave/bin/octave-cli" "$JL/liboctavecli.so"
cp -f "$GP" "$JL/libgnuplot.so"
chmod 755 "$JL/liboctavecli.so" "$JL/libgnuplot.so"
rm -f "$A/octave/bin/octave-cli"

echo "== 4. libraries Octave links but does not install =="
cp -L "$P/openblas/lib/libopenblas.so" "$A/deps/"
cp "$P/fftw/lib/libfftw3.so" "$P/fftw/lib/libfftw3_threads.so" \
   "$P/fftw/lib/libfftw3f.so" "$P/fftw/lib/libfftw3f_threads.so" "$A/deps/"
"$TC/bin/llvm-strip" --strip-unneeded "$A/deps/libopenblas.so" "$A/deps/libfftw3"*.so
# libc++_shared goes next to the executables so gnuplot (run from nativeLibraryDir)
# and octave-cli (LD_LIBRARY_PATH) resolve the same copy.
cp -f "$TC/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$JL/"

echo "== 5. size =="
du -sh "$A" "$A/octave" "$A/deps" "$JL/liboctavecli.so" "$JL/libgnuplot.so"
