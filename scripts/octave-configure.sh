#!/usr/bin/env bash
# Octave route B: extract the source, pull Termux's build recipe for its exact
# ac_cv_* answers, then run the cross configure.
set -uo pipefail

ROOT="$HOME/octave-android"
DL="$ROOT/downloads"
SRC="$ROOT/src"
P="$ROOT/prefix/arm64-v8a"
LOGS="$ROOT/logs"
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

mkdir -p "$SRC" "$LOGS"

if [ ! -d "$SRC/octave-11.3.0" ]; then
  echo "[extract] octave-11.3.0"
  tar -xf "$DL/octave-11.3.0.tar.xz" -C "$SRC" || { echo "EXTRACT_FAILED"; exit 1; }
fi
echo "[extract] ok"

# Termux's recipe: the authoritative source of the bionic ac_cv_* answers.
if [ ! -s "$DL/termux-octave-build.sh" ]; then
  curl -sSL --max-time 60 -o "$DL/termux-octave-build.sh" \
    https://raw.githubusercontent.com/termux/termux-packages/master/packages/octave/build.sh || true
fi
echo "[termux recipe] $(wc -l < "$DL/termux-octave-build.sh" 2>/dev/null || echo 0) lines"
if [ -s "$DL/termux-octave-build.sh" ]; then
  echo "--- ac_cv / TERMUX_PKG_EXTRA_CONFIGURE_ARGS ---"
  grep -nE 'ac_cv|CONFIGURE_ARGS|with-|without-|disable-|enable-' "$DL/termux-octave-build.sh" | head -80
fi

cd "$SRC/octave-11.3.0"
echo "=== configure --help (feature switches) ==="
./configure --help 2>&1 | grep -E '^\s+--(with|without|enable|disable)' | head -120
echo "CONFIGURE_HELP_DONE"
