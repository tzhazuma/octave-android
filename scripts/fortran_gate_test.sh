#!/usr/bin/env bash
# Reproduce the Fortran cross-compilation gate test end to end:
#   Fortran source --(host flang, --target=aarch64-linux-android)--> .o
#                  --(NDK clang + Termux prebuilt Fortran runtime)--> aarch64 ELF
#                  --(adb)--> runs on the device, no Termux involved.
#
# This is the experiment that proves route B's biggest uncertainty is resolved.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/env.sh"

WORK="$OCTAVE_ANDROID_ROOT/spike/fortran-gate"
DEV="${ANDROID_SERIAL:-}"
mkdir -p "$WORK"
cd "$WORK"

[ -x "$FLANG_BIN" ] || { echo "flang not found at $FLANG_BIN -- run: brew install flang"; exit 1; }
[ -f "$FLANG_RT_LIB" ] || { echo "missing $FLANG_RT_LIB -- run: $HERE/fetch_flang_runtime.sh"; exit 1; }

echo "==> [1/3] flang: compile Fortran for $TARGET_TRIPLE (API $ANDROID_API)"
"$FLANG_BIN" --target="$TARGET_TRIPLE$ANDROID_API" -O2 -fPIC -c fscale.f90 -o fscale.o
"$READELF" -h fscale.o | grep -E 'Class|Machine|Type'
echo "    symbols (expect f77 ABI names with trailing underscore):"
"$NM" fscale.o | grep -E ' T '

echo "==> [2/3] NDK clang: link against the prebuilt Fortran runtime"
"$CC_TARGET" -O2 -fPIC driver.c fscale.o -o gate \
  -L"$FLANG_RT_DIR" -lflang_rt.runtime \
  $ANDROID_LDFLAGS -lm
"$READELF" -h gate | grep -E 'Class|Machine|Type'

echo "==> [3/3] run on device"
if [ -z "$DEV" ]; then
  echo "    ANDROID_SERIAL not set; skipping device run."
  echo "    Set it (e.g. ANDROID_SERIAL=<host>:<port>) and re-run to execute on hardware."
  echo "    Expected output: FORTRAN_GATE_OK fscale -> 2.5 5.0 7.5 10.0  fdot=25.0"
  exit 0
fi
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
"$ADB" -s "$DEV" push gate /data/local/tmp/gate
"$ADB" -s "$DEV" shell 'chmod 755 /data/local/tmp/gate; /data/local/tmp/gate; echo "EXIT_RC=$?"'
