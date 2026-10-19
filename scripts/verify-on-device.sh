#!/usr/bin/env bash
# On-device verification for the Octave port.
#
# Two things cannot be checked from the build log and must be seen on hardware:
#   1. the native self-test (OpenBLAS / FFTW / ARPACK / qrupdate) still passes in the
#      shipped APK, and
#   2. a .m file really round-trips through Android's document picker -- the picker has
#      to appear, the file has to come back into the editor, and the bytes on disk have
#      to change when Save writes to the same URI.
#
# The SAF half is driven by hand because the picker UI differs per ROM (on the vivo
# PA2573 com.android.documentsui is a shim and the real picker is vivo's file manager),
# so the script stops and tells you what to tap instead of guessing coordinates.
set -uo pipefail

ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
DEV="${1:-${ANDROID_SERIAL:-}}"
PKG=org.octave.android
TESTFILE=/sdcard/Download/octtest.m
APK="${APK:-$HOME/Downloads/Octave-0.2.0-android-arm64.apk}"

say() { printf '\n== %s\n' "$*"; }
dev() { if [ -n "$DEV" ]; then "$ADB" -s "$DEV" "$@"; else "$ADB" "$@"; fi; }

say "device"
if [ -z "$DEV" ]; then
  DEV=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')
  [ -n "$DEV" ] || { echo "no device: run 'adb connect <ip>:<port>' first"; exit 1; }
fi
echo "using $DEV"

say "screen state (the ROM blanks screencap and swallows input behind a secure keyguard)"
dev shell "dumpsys window policy | grep -m1 'showing='" || true
if dev shell "dumpsys window policy | grep -q 'showing=true'"; then
  echo "KEYGUARD IS UP -- unlock the phone before continuing."
  echo "If the lock screen was disabled by a previous run, restore it with:"
  echo "  adb shell locksettings set-disabled false"
  exit 2
fi

say "install $APK"
if [ -f "$APK" ]; then
  dev push "$APK" /data/local/tmp/octave.apk >/dev/null
  dev shell pm install -r -t /data/local/tmp/octave.apk | tail -1
  dev shell rm -f /data/local/tmp/octave.apk
else
  echo "APK not found at $APK -- keeping the installed build"
fi
dev shell "dumpsys package $PKG | grep -E 'versionName|lastUpdateTime'"

say "test file"
dev push /dev/stdin "$TESTFILE" <<'EOF' 2>/dev/null || echo "keeping the existing $TESTFILE"
% Octave on Android: SAF round-trip test
x = 41; y = 1;
printf('before-edit: %d\n', x + y);
EOF
dev shell "cat $TESTFILE"

say "launch"
dev shell am force-stop $PKG
dev logcat -c
dev shell am start -n "$PKG/.MainActivity" >/dev/null
echo "waiting for the session (assets are unpacked on first launch)"
for _ in $(seq 1 20); do
  sleep 3
  if dev logcat -d -s Octave:I 2>/dev/null | grep -q 'exec:'; then break; fi
done
dev logcat -d -s Octave:I | tail -3

dump() { dev shell uiautomator dump /data/local/tmp/ui.xml >/dev/null 2>&1; dev pull /data/local/tmp/ui.xml /tmp/oct-ui.xml >/dev/null 2>&1; }
console() { /usr/bin/python3 - <<'PY'
import re, html
s = open('/tmp/oct-ui.xml', encoding='utf-8', errors='replace').read()
for t in re.findall(r'text="([^"]*)"', s):
    t = html.unescape(t)
    if 'octave:' in t or 'self-test' in t:
        print(t)
        break
PY
}

say "1/2 native self-test"
dump
BOUNDS=$(grep -o 'text="Self-test"[^>]*bounds="[^"]*"' /tmp/oct-ui.xml | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' | head -1)
if [ -n "$BOUNDS" ]; then
  set -- $BOUNDS
  dev shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
  sleep 6
  dump
  console | tr '\n' '\n' | grep -iE 'LAPACK|FFTW|ARPACK|dgesv|r2c|dsaupd|self-test' | head -20
else
  echo "Self-test button not found in the UI dump; is the activity in front?"
fi

say "2/2 SAF round-trip (manual picker step)"
cat <<EOF
Tap "Open .m" in the app, then pick $TESTFILE from the picker
(storage > Download). When the editor shows the script, come back here and press Enter.
EOF
read -r _
dump
OPENER=$(console | grep -o 'opened [^ ]*' | head -1)
echo "editor state: ${OPENER:-opened-file-not-detected}"

echo "--- editing: appending a marker line through the editor"
dev shell input tap 1500 1700          # focus the editor
dev shell input keyevent 123           # move caret to end (MOVE_END)
dev shell "input text '\n% edited-by-verify-script'"
sleep 1
SAVE=$(grep -o 'text="Save"[^>]*bounds="[^"]*"' /tmp/oct-ui.xml | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' | head -1)
if [ -n "$SAVE" ]; then
  set -- $SAVE
  dev shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
  sleep 3
else
  echo "Save button not found; tap it by hand"
fi

say "result: the file on disk"
dev shell "cat $TESTFILE"
dev shell "cat $TESTFILE" | grep -q 'edited-by-verify-script' \
  && echo "PASS: the edit reached the file through SAF" \
  || echo "FAIL: the file on disk does not contain the edit"
