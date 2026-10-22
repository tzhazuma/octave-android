# org.octave.gui startup abort — resolved (2026-10-23)

Device: vivo PA2573, Android 16/arm64 (`192.168.0.108:41129`).
Package: `org.octave.gui` 0.2.0 (release, non-debuggable final build).
Result: **the Qt GUI starts and runs** — main window, `octave:1>` prompt, and the
interpreter evaluates code. No FORTIFY abort, no tombstone on the startup path.

## What was actually wrong

Two independent defects, the second hidden by the first.

### 1. Octave was not in GUI mode — the real cause of the FORTIFY abort

`cmdline_options` defaults `m_gui = false` (`src/octave.cc:150`). A real
`octave-gui` process is always started by the `octave` launcher, which inserts
the `--gui` option before exec'ing it (`src/main.cc:426-427`). Android's QtLoader
calls the library's exported `main()` with `argc = 1` and no `--gui`, so
`qt_application::start_gui_p()` returned false.

`base_qobject` then created a `QApplication` and ran Octave in CLI mode. stdin in
an Android app is at EOF, so the interpreter shut down immediately and
`qt_application::execute()` returned 0 after **164 ms**. `main()` returned to
Qt's `qtMainLoopThread`, Qt/Android tore the process down, and ~620 ms later a
*different* thread locked a destroyed pthread mutex, which bionic reports as:

```
F libc : FORTIFY: pthread_mutex_lock called on a destroyed mutex (0x…)
```

That abort is a **teardown symptom**, not the startup fault. It explains every
puzzling observation: no tombstone (this is bionic's `__libc_fatal`, i.e.
`_exit`), no Qt logging after start-up (Octave's `base_qobject` installs a no-op
`qMessageLogHandler` — see `libgui/src/octave-qobject.cc:144,208`), and the
~750 ms delay after the activity appeared.

Probe evidence (instrumented libOctaveGui, 03:51 run, no `--gui`):

```
I OctaveProbe: === main ENTER, pid 9344, tid 9377, argc 1 ===
I OctaveProbe: qt_application::ctor ENTER (org=octave app=octave-gui ver=11.3.0 argc=1)
I OctaveProbe: qt_application::ctor RETURN
I OctaveProbe: qt_application::execute ENTER
I OctaveProbe: qt_application::execute RETURN 0          (164 ms later)
I OctaveProbe: === main RETURN 0 ===
F libc       : FORTIFY: pthread_mutex_lock called on a destroyed mutex (0x719876a0a8)   (620 ms later, tid 9375)
```

Fix: pass the option the launcher would have passed, through Qt's documented
manifest mechanism:

```xml
<meta-data android:name="android.app.arguments" android:value="--gui"/>
```

Verified by the probe: `argv[1]=--gui`.

### 2. Desktop OpenGL surface format on a GLES-only platform

With GUI mode selected, startup reached main-window composition and died in Qt:

```
F libc: Fatal signal 6 (SIGABRT) ... tid 12040 (qtMainLoopThrea)
tombstone #03 QMessageLogger::fatal
          #04-#07 libplugins_platforms_qtforandroid_arm64-v8a.so
          #08 QOpenGLContext::makeCurrent(QSurface*)
          #11 QRhi::create(...)
          #12 QBackingStoreRhiSupport::create()
          #13 QPlatformBackingStore::createRhi(...)
          #14 QRhiBackingStore::flush(...)
          #16 QWidgetRepaintManager::flush(...)
```

Qt's strings identify it as `QEGLPlatformContext: Failed to create context: %x`
/ `eglMakeCurrent failed: %x`. The cause is in Octave, not Qt: `base_qobject`'s
constructor unconditionally asks for a **desktop OpenGL compatibility profile**:

```c++
QSurfaceFormat fmt;
fmt.setRenderableType (QSurfaceFormat::OpenGL);
fmt.setProfile (QSurfaceFormat::CompatibilityProfile);
fmt.setOption (QSurfaceFormat::DeprecatedFunctions, true);
QSurfaceFormat::setDefaultFormat (fmt);          // libgui/src/octave-qobject.cc:234-240
```

Android EGL only provides OpenGL ES, so every Qt window fails to make its
context current.

Fix: keep the request on desktop platforms, skip it on Android:

```c++
#if QT_VERSION >= QT_VERSION_CHECK(5, 4, 0) && ! defined (Q_OS_ANDROID)
```

The desktop-GL entry points Octave's own plot renderer needs are supplied by
gl4es (it initialises fine: `Initialising gl4es v1.1.7 … Using GLES 2.0 backend`).

### 3. Make qFatal() visible again (diagnostic)

Because `base_qobject` replaces the Qt message handler with a no-op unless
`OCTAVE_SHOW_GUI_MESSAGES` is set, the fatal EGL message was swallowed. Set:

```
OCTAVE_SHOW_GUI_MESSAGES=1
```

in `OctaveApplication.onCreate`.

## Evidence after the fixes

Instrumented run (04:09), `--gui` + guard:

```
I OctaveProbe: === main ENTER, pid 14133, tid 14180, argc 2 ===
I OctaveProbe:   argv[1]=--gui
I OctaveProbe: qt_application::execute ENTER
I OctaveProbe: Qt: … QWidgetWindow(…, name="MainWindowWindow") …
I OctaveProbe: heartbeat 400 (stage 30, tid 789)     ← 60 s of event loop, no execute RETURN
```

Then, at the GUI prompt: `disp(2+2)` → `4`, `octave:2>`.
Screenshots in this directory:

* `octave-gui-1.png` — "Welcome to Octave!" first-run wizard rendered
* `octave-gui-5.png` — main window, `octave:1>` prompt (probe build)
* `octave-gui-6.png` — `disp(2+2)` → `4` (probe build)
* `octave-gui-clean2.png` — final clean build, main window + prompt

Final clean build (no probe library, `debuggable` removed): process alive, crash
buffer empty, GUI focused and rendering. APK sha256
`86c9253c3ce9cbe4dcb08d14b8dc8dfc72c6c1b90a092fc5a644b30f042d1475`.

## Changes

| File | Change |
|---|---|
| `android-gui-app/app/src/main/AndroidManifest.xml` | `<meta-data android:name="android.app.arguments" android:value="--gui"/>` |
| `src/octave-11.3.0/libgui/src/octave-qobject.cc` | `&& ! defined (Q_OS_ANDROID)` on the desktop-OpenGL default format (`src/` is gitignored; patch saved as `patches/octave-android-gles-surface-format.patch`) |
| `android-gui-app/app/src/main/java/org/octave/gui/OctaveApplication.java` | `OCTAVE_SHOW_GUI_MESSAGES=1` |
| `scripts/gui-shared-link.sh` | production link step, in-tree and reproducible |
| `scripts/gui-shared-link-probe.sh`, `gui-probe/gui-main-probe.cc` | startup probe: objcopy renames Octave's `main` to `octave_real_main`, wrapper logs entry/exit, installs a logcat Qt handler, redirects stderr to `$HOME/octave-gui.log`, wraps `qt_application::ctor`/`execute` with `-Wl,--wrap` |

`jniLibs/arm64-v8a/liboctgui.so` and `libOctaveGui_arm64-v8a.so` were rebuilt
(they are gitignored), and the APK reinstalled.

### Rebuilding after the source patch

`make` in the tree wants to rebuild ~1080 objects because the extract's
timestamps are stale relative to the dependency files. Rebuild only the patched
object and relink instead (~5 s):

```sh
cd ~/octave-android/src/octave-11.3.0
# 1. compile (command taken from `make -n libgui/liboctgui.la`)
sh -c '<the libtool compile line for libgui_src_la-octave-qobject.lo>'
# 2. replace it in the convenience archive
$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-ar r \
    libgui/src/.libs/libgui-src.a libgui/src/.libs/libgui_src_la-octave-qobject.o
$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-ranlib libgui/src/.libs/libgui-src.a
# 3. relink liboctgui (command taken from the same `make -n` output)
sh -c '<the libtool link line for libgui/liboctgui.la>'
cp libgui/.libs/liboctgui.so ~/octave-android/android-gui-app/jniLibs/arm64-v8a/
# 4. relink the app library, build the APK, install
~/octave-android/scripts/gui-shared-link.sh --deploy
cd ~/octave-android/android-gui-app && gradle :app:assembleRelease  # JAVA_HOME=jdk21
~/install-apk.sh app/build/outputs/apk/release/app-release.apk
```

## Open items

* **Normal-exit teardown was not exercised conclusively.** The FORTIFY abort was
  caused by `main()` returning; while the event loop runs it is gone. Ctrl+Q /
  Back did not produce a clean quit test because another agent force-stopped the
  process mid-test. If Octave is ever made to return from `main()`, the old
  Qt/Android teardown abort may reappear; this is a shutdown bug, not a startup
  bug.
* `/system/xbin/gnuplot: Permission denied` is printed once at startup. The
  gnuplot binary ships as `jniLibs/.../libgnuplot.so`; the GUI path still looks
  for it under `PATH`. Plotting backends need a separate look.
* Plotting with the GLES context (and gl4es for desktop-GL calls) is untested.
* `MainActivity`/manifest still carry FreeCAD-era labels and comments; untouched.
