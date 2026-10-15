#!/system/bin/sh
# Runs ON THE DEVICE via `adb shell sh /sdcard/Download/device_run.sh`
# Invokes Termux RUN_COMMAND properly (no cross-shell quoting issues).
LOG=/sdcard/Download/device_log.txt
: > $LOG

echo "== step1: allow-external-apps property ==" >> $LOG
cat /data/data/com.termux/files/home/.termux/termux.properties >> $LOG 2>&1
echo "" >> $LOG

echo "== step2: start RunCommandService ==" >> $LOG
am start-foreground-service \
  -a com.termux.RUN_COMMAND \
  -n com.termux/.app.RunCommandService \
  --es com.termux.RUN_COMMAND_PATH /data/data/com.termux/files/usr/bin/sh \
  --esa com.termux.RUN_COMMAND_ARGUMENTS "-c,echo RUN_OK > /sdcard/Download/marker.txt" \
  --ez com.termux.RUN_COMMAND_BACKGROUND true \
  com.termux >> $LOG 2>&1
sleep 4

echo "== step3: marker file ==" >> $LOG
ls -la /sdcard/Download/marker.txt >> $LOG 2>&1
echo "-- content --" >> $LOG
cat /sdcard/Download/marker.txt >> $LOG 2>&1
echo "== END ==" >> $LOG
cat $LOG
