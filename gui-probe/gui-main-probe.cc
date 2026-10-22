// Startup probe for GNU Octave's Qt GUI on Android.
//
// Qt's loader dlopen()s libOctaveGui_arm64-v8a.so, dlsym()s "main" and calls
// it on the "qtMainLoopThread".  Octave's own main() is renamed to
// octave_real_main() at link time (llvm-objcopy --redefine-sym) so this file
// supplies the real entry point and can report:
//
//   * whether main is entered at all, and what argv/environment it gets,
//   * which thread it runs on,
//   * every Qt message (qDebug/qWarning/qFatal) via a message handler that is
//     installed before QApplication exists,
//   * Octave's std::cerr/std::cout, redirected to $HOME/octave-gui.log,
//   * the load addresses of the interesting libraries, and whether the mutex
//     address from the FORTIFY abort falls inside one of them,
//   * entry/exit of octave::qt_application's constructor and execute(), which
//     bracket QApplication construction and the whole GUI start-up,
//   * whether main ever returns.
//
// Diagnostics are tagged "OctaveProbe" and also appended to
// $HOME/octave-gui.log so they survive logcat rotation.

#include <android/log.h>

#include <dlfcn.h>
#include <pthread.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include <QtCore/QByteArray>
#include <QtCore/QCoreApplication>
#include <QtCore/QString>
#include <QtCore/qlogging.h>

// main-gui.cc's main(), renamed by objcopy.
extern "C" int octave_real_main (int argc, char **argv);

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

namespace
{

constexpr const char *kTag = "OctaveProbe";

std::atomic<bool> g_beat{true};
std::atomic<int> g_stage{0};
FILE *g_log = nullptr;

long
probe_tid ()
{
  return static_cast<long> (syscall (__NR_gettid));
}

void
probe_log (const char *fmt, ...)
{
  char buf[1200];

  va_list ap;
  va_start (ap, fmt);
  vsnprintf (buf, sizeof (buf), fmt, ap);
  va_end (ap);

  __android_log_print (ANDROID_LOG_INFO, kTag, "%s", buf);

  if (g_log)
    {
      fprintf (g_log, "[probe] %s\n", buf);
      fflush (g_log);
    }
}

void
qt_message_handler (QtMsgType type, const QMessageLogContext &ctx,
                    const QString &msg)
{
  int pri = ANDROID_LOG_INFO;

  switch (type)
    {
    case QtDebugMsg:    pri = ANDROID_LOG_DEBUG; break;
    case QtInfoMsg:     pri = ANDROID_LOG_INFO;  break;
    case QtWarningMsg:  pri = ANDROID_LOG_WARN;  break;
    case QtCriticalMsg: pri = ANDROID_LOG_ERROR; break;
    case QtFatalMsg:    pri = ANDROID_LOG_FATAL; break;
    }

  const QByteArray text = msg.toUtf8 ();

  __android_log_print (pri, kTag, "Qt: %s (%s:%d)",
                       text.constData (),
                       ctx.file ? ctx.file : "?", ctx.line);

  if (g_log)
    {
      fprintf (g_log, "[qt] %s (%s:%d)\n",
               text.constData (), ctx.file ? ctx.file : "?", ctx.line);
      fflush (g_log);
    }
}

void
dump_env ()
{
  static const char *keys[] = {
    "HOME", "OCTAVE_HOME", "OCTAVE_EXEC_PREFIX", "OCTAVE_ARCHLIBDIR",
    "LD_LIBRARY_PATH", "PATH", "QT_QPA_PLATFORM", "QT_DEBUG_PLUGINS",
    "QT_LOGGING_RULES", "LIBGL_NOTEST", "TMPDIR"
  };

  for (const char *k : keys)
    {
      const char *v = getenv (k);
      probe_log ("env %s=%s", k, v ? v : "(unset)");
    }
}

// The FORTIFY message in the bug report always names 0x74912ea6d8.  If that
// address is even mapped at start-up, this says which module owns it.
void
inspect_crash_address ()
{
  const unsigned long suspect = 0x74912ea6d8UL;

  Dl_info info;
  memset (&info, 0, sizeof (info));

  if (dladdr (reinterpret_cast<void *> (suspect), &info) && info.dli_fname)
    probe_log ("suspect %#lx -> %s (%s)", suspect, info.dli_fname,
               info.dli_sname ? info.dli_sname : "?");
  else
    probe_log ("suspect %#lx is not inside any loaded module", suspect);
}

void
dump_maps ()
{
  FILE *f = fopen ("/proc/self/maps", "r");
  if (!f)
    return;

  static const char *needles[] = {
    "libOctaveGui", "liboctgui", "liboctinterp", "liboctave.so",
    "libQt6Core", "libQt6Gui", "libQt6Widgets", "libQt6Android",
    "libc++_shared", "libGL.so", "libc.so", "liblog.so", "libopenblas",
    "qtforandroid", "libplugins"
  };

  char line[1024];
  while (fgets (line, sizeof (line), f))
    {
      for (const char *n : needles)
        {
          if (strstr (line, n))
            {
              // strip the trailing newline so logcat stays one line per map
              char *nl = strchr (line, '\n');
              if (nl)
                *nl = '\0';
              probe_log ("map %s", line);
              break;
            }
        }
    }

  fclose (f);
}

// Surviving the ~700 ms wall is the whole point of the heartbeat.
void *
heartbeat_thread (void *)
{
  for (int i = 1; g_beat.load () && i <= 400; ++i)
    {
      usleep (150 * 1000);
      if (! g_beat.load ())
        break;
      probe_log ("heartbeat %d (stage %d, tid %ld)", i, g_stage.load (),
                 probe_tid ());
    }

  return nullptr;
}

}  // namespace

// ---------------------------------------------------------------------------
// octave::qt_application constructor / execute() wrappers
//
// --wrap rewrites the references *inside main-gui.o*, and these two calls are
// the only things Octave's main does; everything else happens inside them.
// ---------------------------------------------------------------------------

extern "C" void
real_qt_application_ctor (void *self, const std::string &org,
                          const std::string &app, const std::string &ver,
                          int argc, char **argv)
  __asm__ ("__real__ZN6octave14qt_applicationC1ERKNSt6__ndk112basic_string"
           "IcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_S9_iPPc");

extern "C" void
wrap_qt_application_ctor (void *self, const std::string &org,
                          const std::string &app, const std::string &ver,
                          int argc, char **argv)
  __asm__ ("__wrap__ZN6octave14qt_applicationC1ERKNSt6__ndk112basic_string"
           "IcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_S9_iPPc");

extern "C" int
real_qt_application_execute (void *self)
  __asm__ ("__real__ZN6octave14qt_application7executeEv");

extern "C" int
wrap_qt_application_execute (void *self)
  __asm__ ("__wrap__ZN6octave14qt_application7executeEv");

extern "C" void
wrap_qt_application_ctor (void *self, const std::string &org,
                          const std::string &app, const std::string &ver,
                          int argc, char **argv)
{
  probe_log ("qt_application::ctor ENTER (org=%s app=%s ver=%s argc=%d)",
             org.c_str (), app.c_str (), ver.c_str (), argc);
  for (int i = 0; i < argc && i < 16; ++i)
    probe_log ("  argv[%d]=%s", i, argv[i] ? argv[i] : "(null)");

  g_stage = 10;

  real_qt_application_ctor (self, org, app, ver, argc, argv);

  g_stage = 20;
  probe_log ("qt_application::ctor RETURN");
}

extern "C" int
wrap_qt_application_execute (void *self)
{
  probe_log ("qt_application::execute ENTER");
  g_stage = 30;

  int ret = real_qt_application_execute (self);

  g_stage = 40;
  probe_log ("qt_application::execute RETURN %d", ret);

  return ret;
}

extern "C" int
main (int argc, char **argv)
{
  // Octave's diagnostics (including option-parse errors) go to std::cerr,
  // which Android sends to /dev/null.  Give them a file that survives.
  const char *home = getenv ("HOME");
  if (home)
    {
      char path[1024];
      snprintf (path, sizeof (path), "%s/octave-gui.log", home);
      g_log = fopen (path, "a");
      if (g_log)
        setvbuf (g_log, nullptr, _IONBF, 0);
    }

  probe_log ("=== main ENTER, pid %d, tid %ld, argc %d ===",
             static_cast<int> (getpid ()), probe_tid (), argc);

  for (int i = 0; i < argc && i < 16; ++i)
    probe_log ("  argv[%d]=%s", i, argv[i] ? argv[i] : "(null)");

  // Redirect C++ streams to the log file before Octave touches them.
  if (g_log)
    {
      dup2 (fileno (g_log), STDOUT_FILENO);
      dup2 (fileno (g_log), STDERR_FILENO);
    }

  qInstallMessageHandler (qt_message_handler);

  dump_env ();
  inspect_crash_address ();
  dump_maps ();

  pthread_t beat;
  if (pthread_create (&beat, nullptr, heartbeat_thread, nullptr) == 0)
    pthread_detach (beat);

  probe_log ("calling octave_real_main");
  g_stage = 1;

  int ret = octave_real_main (argc, argv);

  g_stage = 99;
  g_beat = false;

  probe_log ("=== main RETURN %d ===", ret);
  probe_log ("QCoreApplication::instance() is %s",
             QCoreApplication::instance () ? "non-null" : "null");

  return ret;
}
