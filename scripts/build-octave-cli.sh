#!/usr/bin/env bash
# Link octave-cli, which the plain `make` cannot do, and install the tree.
#
# `make` gets all the way to `src/octave-cli` and then fails, for two unrelated reasons:
#
#   a) liboctave.so and liboctinterp.so call __divsc3 / __powisf2 / __powidf2 and the
#      __aarch64_* outline atomics, but neither DSO links libclang_rt.builtins. The
#      definitions therefore only reach the executable, where they are hidden, and lld
#      refuses: "non-exported symbol '__divsc3' ... is referenced by DSO 'liboctave.so'".
#      Fix: re-archive the builtins members with DEFAULT visibility so the executable
#      can export them for its DSOs.
#
#   b) bionic's libm does not carry the C99 complex functions Octave uses (clogf).
#      Octave's own implementations were built into build/complexmath/*.o by an earlier
#      step; they need to be linked in.
#
# With both supplied, the same libtool link line succeeds. `make install` then needs to
# be told not to re-link (it would fail again and delete the binary): -o src/octave-cli.
set -euo pipefail

ROOT="$HOME/octave-android"
SRC="$ROOT/src/octave-11.3.0"
NDK="$HOME/Library/Android/sdk/ndk/28.2.13676358"
TC="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

cd "$SRC"

echo "== 1. record the link command make would use =="
make V=1 src/octave-cli > /tmp/octave-cli-link.log 2>&1 || true
LINK=$(sed -n 's/^libtool: link: //p' /tmp/octave-cli-link.log | head -1)
[ -n "$LINK" ] || { echo "no libtool link line in /tmp/octave-cli-link.log"; exit 1; }

echo "== 2. builtins archive with default visibility =="
rm -rf /tmp/octcompat && mkdir -p /tmp/octcompat/m && cd /tmp/octcompat/m
"$TC/bin/llvm-ar" x "$TC/lib/clang/19/lib/linux/libclang_rt.builtins-aarch64-android.a"
for o in *.o; do
  for s in __aarch64_cas1_acq_rel __aarch64_cas4_acq_rel __aarch64_ldadd4_acq_rel \
           __aarch64_ldadd8_acq_rel __aarch64_ldadd8_relax __divsc3 __powidf2 __powisf2; do
    "$TC/bin/llvm-objcopy" --set-symbol-visibility=$s=default "$o" "$o.tmp" 2>/dev/null \
      && mv "$o.tmp" "$o" || rm -f "$o.tmp"
  done
done
"$TC/bin/llvm-ar" rcs /tmp/octcompat/libbuiltins-default.a *.o

echo "== 3. relink with the complex-math objects and the patched archive =="
cd "$SRC"
COMPLEX=$(ls "$ROOT"/build/complexmath/*.o | tr '\n' ' ')
eval "$LINK $COMPLEX /tmp/octcompat/libbuiltins-default.a"
cp -f src/.libs/octave-cli src/octave-cli
chmod +x src/octave-cli

echo "== 4. install, without re-linking =="
make install -o src/octave-cli

echo "== 5. result =="
ls -la "$ROOT/prefix/arm64-v8a/octave/bin/octave-cli"
"$TC/bin/llvm-readelf" -d "$ROOT/prefix/arm64-v8a/octave/bin/octave-cli" | grep NEEDED
