# GNU Octave → Android

Porting GNU Octave to Android as a **native deliverable** (standalone APK preferred).

**Read [`STATUS.md`](STATUS.md) first** — it is the single source of truth: current
status, the full command/error log, evidence index, and next steps.

---

## Status in one screen

| Track | State |
|---|---|
| **Route B — NDK native cross-build** | ✅ **GO.** The blocking uncertainty (Fortran) is resolved. |
| **Route A — Termux host** | ✅ Working, archived as the verified fallback. |

### Device-verified on real hardware (Android 16 / arm64-v8a), no Termux involved

| Component | Evidence |
|---|---|
| **FFTW 3.3.10** | `fftw-wisdom --version` → `FFTW version 3.3.10` |
| **OpenBLAS 0.3.34** (BLAS) | `dgemm` → `[19 22 ; 43 50]` |
| **OpenBLAS 0.3.34** (+ full LAPACK) | `dgesv` → `x = [0.090909, 0.636364]` = exactly `[1/11, 7/11]`; `dpotrf` Cholesky verified |
| **Fortran gate** | `FORTRAN_GATE_OK fscale -> 2.5 5.0 7.5 10.0  fdot=25.0` |

---

## The two findings that unblocked route B

**1. Fortran cross-compilation works — with zero LLVM builds.**

The NDK ships no Fortran compiler, and building LLVM+flang from source needs
~40 GiB (this box had ~15). Instead:

- `brew install flang` → host **flang 23.1.3** (a bottle; depends on the llvm already present)
- The aarch64 Fortran **runtime** is a **1.07 MB** prebuilt from Termux's
  [`ndk-toolchain-clang-with-flang` r30](https://github.com/termux/ndk-toolchain-clang-with-flang/releases/tag/r30)
  release → `libflang_rt.runtime.a` (117 members, all ELF64/AArch64, zero libc++
  dependencies, sha256 verified against Termux's own pinned value)

```sh
flang-new --target=aarch64-linux-android24 -O2 -fPIC -c fscale.f90 -o fscale.o
$NDK/.../aarch64-linux-android24-clang driver.c fscale.o -o gate \
  -L$FLANG_RT_DIR -lflang_rt.runtime -Wl,-z,max-page-size=16384 -lm
```

**2. LAPACK needs no Fortran compiler at all.**

OpenBLAS ships an **f2c-converted LAPACK in C** — `lapack-netlib/SRC/*.c`,
2067 files. Of 2046 `.f` files only `dbddsc` and `sbddsc` lack a C counterpart.
The switch is `C_LAPACK=1` (`lapack-netlib/SRC/Makefile:60`):

```sh
gmake OSNAME=Android ARCH=arm64 TARGET=ARMV8 CROSS=1 HOSTCC=/usr/bin/clang \
  NOFORTRAN=1 C_LAPACK=1 ...      # -> zero undefined _FortranA* symbols
```

The resulting library needs neither a Fortran compiler nor a Fortran runtime.

---

## Reproducing

```sh
scripts/fetch_flang_runtime.sh                 # 1 MB runtime, sha256-verified
scripts/build_fftw.sh                          # FFTW 3.3.10
OPENBLAS_MODE=clapack scripts/build_openblas.sh  # OpenBLAS + full LAPACK, pure C
ANDROID_SERIAL=<host>:<port> scripts/fortran_gate_test.sh   # Fortran gate, on device
```

`scripts/env.sh` holds the shared environment. It documents two traps that each
cost a failed build:

- `which clang` resolves to the **ATfE bare-metal toolchain**, which has no host
  sysroot (`stdio.h` not found). `HOSTCC` is pinned to `/usr/bin/clang`.
- `make install` needs `OSNAME=Android` too, or it emits `.dylib` symlinks
  instead of `.so`.

Every artifact is linked with `-Wl,-z,max-page-size=16384`, so LOAD segments are
**16 KiB aligned** as Android 15/16 requires, and depends only on bionic
(`libm` / `libdl` / `libc`).

---

## Layout

```
STATUS.md     full status, command/error log, evidence index, next steps
evidence/     device run transcripts, screenshots, ELF/symbol proofs
scripts/      reproducible build + device-test scripts
spike/        the gate experiments (Fortran, BLAS, LAPACK) with their sources
logs/         selected build logs
```

---

## The Qt GUI: how it starts, and why it took so long

The GUI is the real thing — `octave-gui`'s `main` linked as a shared object
(`libOctaveGui_arm64-v8a.so`), loaded by QtLoader, hosted by a `QtActivity`. On device it comes
up with the Command Window, File Browser, Workspace, Command History and Documentation panels
and a live `octave:1>` prompt.

Getting there meant finding two bugs in series, and the second was invisible until the first was
fixed.

### 1. It was running in CLI mode

`cmdline_options` initialises `m_gui` to `false`, and the real `octave` launcher always inserts
`--gui` before exec'ing `octave-gui`. QtLoader calls our `main` with `argc == 1`, so
`start_gui_p()` was false, `base_qobject` took the headless path, stdin hit EOF and `execute()`
returned after 164 ms.

Instrumenting `main` before and after each step made this obvious:

```
main ENTER ... argc 1
qt_application::execute RETURN 0     (164 ms)
main RETURN 0
620 ms later, on a different thread: F libc: FORTIFY: pthread_mutex_lock called on a destroyed mutex
```

**That abort was never the cause.** It happens in Qt's teardown *after* `main()` returns, which
is why there was no tombstone, why `logcat -b crash` was empty, and why setting
`QT_DEBUG_PLUGINS`/`QT_LOGGING_RULES` produced nothing — the process was already on its way out.
The fix is one manifest line:

```xml
<meta-data android:name="android.app.arguments" android:value="--gui"/>
```

### 2. It asked for desktop OpenGL on a GLES-only platform

With GUI mode on, `base_qobject` unconditionally requested a desktop compatibility profile
(`QSurfaceFormat` with `RenderableType=OpenGL`, `CompatibilityProfile`, `DeprecatedFunctions`,
`libgui/src/octave-qobject.cc`). Android's EGL cannot provide that, so Qt died in
`QOpenGLContext::makeCurrent → QRhi::create → QMessageLogger::fatal` and aborted the Qt thread.

The message was not visible because Octave installs a Qt message handler that swallows it. Set
`OCTAVE_SHOW_GUI_MESSAGES=1` to see it. The block is now guarded with `! defined (Q_OS_ANDROID)`;
Octave's own plotting entry points still get GL through gl4es.

The patch is saved as `patches/octave-android-gles-surface-format.patch` because `src/` is a
build checkout and is not tracked.

### Rebuilding liboctgui

A full `make` in `src/octave-11.3.0` drags in ~1080 objects through stale dependencies. The
recipe in `evidence/gui-startup-2026-10-23/README.md` rebuilds the single `octave-qobject.cc`
object and relinks, which takes seconds.

### Known rough edges

* Normal-exit teardown is untested; if Octave quits via `main()` returning, the Qt teardown that
  produced the FORTIFY message may still be hit.
* Startup logs `/system/xbin/gnuplot: Permission denied`. gnuplot ships as `libgnuplot.so` in
  `nativeLibraryDir`; the GUI's plotting path still looks on `PATH`.
* The window renders as a narrow letterboxed column. That is layout, not function.
