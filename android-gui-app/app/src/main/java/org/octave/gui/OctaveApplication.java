package org.octave.gui;

import android.app.Application;
import android.content.res.AssetManager;
import android.system.Os;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;

/**
 * Establishes Octave's runtime environment before QtLoader touches a single library.
 *
 * <p>Octave locates its .m files, its architecture directory and the Qt resources the GUI needs
 * through OCTAVE_HOME, and it resolves its own shared libraries through LD_LIBRARY_PATH. Get
 * either wrong and the GUI's main() returns almost immediately: the activity flashes up and the
 * process disappears with no crash at all, which is a miserable thing to debug.
 *
 * <p>One trap in the layout: assets/oct unpacks into files/octave, and inside it the real
 * installation root is another "octave" directory, so OCTAVE_HOME is files/octave/octave.
 */
public class OctaveApplication extends Application {
    private static final String TAG = "OctaveApp";

    @Override public void onCreate() {
        super.onCreate();
        String files = getFilesDir().getAbsolutePath();
        unpackOctaveData(files);

        String home = files + "/octave/octave";
        String nld = getApplicationInfo().nativeLibraryDir;
        set("OCTAVE_HOME", home);
        set("OCTAVE_EXEC_PREFIX", home);
        set("OCTAVE_ARCHLIBDIR", home + "/lib/octave/11.3.0");
        set("OCTAVE_LOCALE_DIR", home + "/share/locale");
        set("OCTAVE_IMAGE_DIR", home + "/share/octave");
        // The binary's DT_RPATH points at the machine that built it, so the search path has to
        // be supplied here; nativeLibraryDir comes first so Qt and libc++_shared resolve to the
        // copies shipped inside the APK.
        set("LD_LIBRARY_PATH", nld + ":" + home + "/lib/octave/11.3.0");
        set("PATH", nld + ":" + home + "/bin:/system/bin:/system/xbin");
        set("HOME", files);
        set("TMPDIR", files);
        set("TERM", "dumb");
        /* gl4es (libGL.so) probes the GPU from its ELF constructor by creating and then
         * destroying its own EGL display, Pbuffer surface and context. That happens during
         * dlopen, before Qt gets a chance to initialise, and it leaves the EGL display in a
         * state where Qt's eglChooseConfig returns no configs -- Qt's Android platform plugin
         * then aborts. LIBGL_NOTEST makes gl4es skip the probe and assume conservative GLES2
         * defaults. This is the same ordering FreeCAD needed. */
        set("LIBGL_NOTEST", "1");
        // Octave's base_qobject installs a no-op Qt message handler unless this is
        // set, which silently swallows qFatal() text (including the EGL/OpenGL
        // error that used to abort start-up). Keep Qt's messages visible.
        set("OCTAVE_SHOW_GUI_MESSAGES", "1");
        // Diagnostic: let Qt report how far it gets. Remove once the startup path is clean.
        set("QT_DEBUG_PLUGINS", "1");
        set("QT_LOGGING_RULES", "qt.core.*=true;qt.qpa.*=true");

        /* No preload of Octave's libraries on purpose. System.loadLibrary("octgui") pulls
         * Qt6Core in before QtLoader has set up the JNI environment, and Qt then aborts with
         * "JNI DETECTED ERROR IN APPLICATION: java_class == null". QtLoader loads the whole set
         * in the right order; the environment above is all it needs from us. */
    }

    /** Copy assets/oct/** into files/octave once, so OCTAVE_HOME points at real files. */
    private void unpackOctaveData(String files) {
        File root = new File(files, "octave");
        File marker = new File(root, ".unpacked-v1");
        if (marker.isFile()) return;
        try {
            long t0 = System.currentTimeMillis();
            copyTree(getAssets(), "oct", root);
            //noinspection ResultOfMethodCallIgnored
            marker.createNewFile();
            Log.i(TAG, "unpacked Octave data in " + (System.currentTimeMillis() - t0) + " ms");
        } catch (IOException e) {
            Log.e(TAG, "could not unpack Octave data", e);
        }
    }

    private static void copyTree(AssetManager assets, String path, File dest) throws IOException {
        String[] children = assets.list(path);
        if (children != null && children.length > 0) {
            //noinspection ResultOfMethodCallIgnored
            dest.mkdirs();
            for (String child : children) copyTree(assets, path + "/" + child, new File(dest, child));
        } else {
            //noinspection ResultOfMethodCallIgnored
            dest.getParentFile().mkdirs();
            try (InputStream in = assets.open(path);
                 FileOutputStream out = new FileOutputStream(dest)) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
        }
    }

    private static void set(String key, String value) {
        try { Os.setenv(key, value, true); } catch (Throwable ignored) { }
    }
}
