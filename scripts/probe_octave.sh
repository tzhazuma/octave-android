#!/data/data/com.termux/files/usr/bin/sh
# Probe Termux environment: octave presence, storage, network.
export PATH=/data/data/com.termux/files/usr/bin:/system/bin:/vendor/bin
P=/data/data/com.termux/files/usr
OUT=/sdcard/Download/oct_out.txt
{
  echo "== date =="; date
  echo "== uname =="; uname -a
  echo "== termux version (dpkg termux-tools) =="; $P/bin/dpkg -s termux-tools 2>&1 | grep -E '^(Package|Version)'
  echo "== octave binary =="; ls -la $P/bin/octave $P/bin/octave-cli 2>&1
  echo "== dpkg -s octave =="; $P/bin/dpkg -s octave 2>&1 | grep -E '^(Package|Version|Status)' 
  echo "== installed pkg count =="; $P/bin/dpkg -l 2>/dev/null | grep -c '^ii'
  echo "== key deps present? =="
  for p in libopenblas fftw qhull readline arpack-ng glpk suitesparse sundials qrupdate-ng libandroid-complex-math gnuplot; do
    st=$($P/bin/dpkg -s $p 2>/dev/null | grep '^Status' | head -1)
    echo "  $p: ${st:-NOT-INSTALLED}"
  done
  echo "== storage =="; df -h /data /sdcard 2>&1
  echo "== network: curl packages.termux.dev =="
  if [ -x $P/bin/curl ]; then
    $P/bin/curl -sI --max-time 15 https://packages.termux.dev 2>&1 | head -3
  else
    echo "no curl binary"
  fi
  echo "== apt sources =="; cat $PREFIX/etc/apt/sources.list 2>&1 | head -5
  echo "== DONE =="
} > $OUT 2>&1
